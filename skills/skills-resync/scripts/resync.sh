#!/usr/bin/env bash
# Mechanical half of skills-resync: resolve upstream, classify drift, re-vendor, clean up.
# Judgement stays in SKILL.md - which protected edits (L1-L6) a skill carries, and whether a
# remaining diff is one of them. Everything this script does is decidable without reading prose.
#
# Usage: resync.sh --refresh                    pull marketplaces, mirror url-pinned plugins
#        resync.sh --check                      classify every skill in inventory.tsv
#        resync.sh --diff <skill>               full diff for one skill
#        resync.sh --snapshot <skill> [...]     record the skill's local edits as a replayable patch
#        resync.sh --apply <skill> [<skill>...] re-vendor, restore regime + local patch, rebase baselines
#        resync.sh --hash <dir>                 print the tree hash the baseline column holds
#        resync.sh --clean [--dry-run]          sweep own leftovers + orphan temp_git_* clones
#        resync.sh --self-test                  exercise apply/regime/patch/baseline paths in a scratch dir
set -euo pipefail

SKILLS_DIR="${SKILLS_DIR:-$HOME/.claude/skills}"
PLUGINS_JSON="${PLUGINS_JSON:-$HOME/.claude/plugins/installed_plugins.json}"
PLUGIN_CACHE="${PLUGIN_CACHE:-$HOME/.claude/plugins/cache}"
MARKETPLACES="${MARKETPLACES:-$HOME/.claude/plugins/marketplaces}"
MIRRORS="${MIRRORS:-$PLUGIN_CACHE/skills-resync-mirror}"
INVENTORY="${INVENTORY:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/inventory.tsv}"
PATCHES="${PATCHES:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/patches}"

# L6 in SKILL.md: local invocation regime, never upstream state. The script owns re-applying it
# because it is one frontmatter line - the edit most likely to be lost, and the only one that is
# purely mechanical. Every diff below ignores it, so a skill whose only local change is L6 reads
# as identical instead of forcing a hand comparison.
#
# The line is *frontmatter state*, and a skill is free to talk about it in prose:
# claude-automation-recommender carries `disable-model-invocation: true  # for user-only` at line
# 188 as an example. An unanchored whole-file grep reads that as "the flag is already set", so
# restore_regime gets skipped and a re-vendor silently promotes a slash-only skill to
# model-invoked - which it did, to that very skill. Every state test goes through has_regime.
REGIME='disable-model-invocation: true'
# ponytail: the diff filter is a regex, so it cannot be scoped to the frontmatter the way
# has_regime is. Anchoring it to the bare `true` form keeps it off documented lines, which all
# carry a trailing comment. Strip the frontmatter line from copies of both trees before diffing
# if a body line ever appears in exactly this form.
REGIME_RE='^disable-model-invocation: *true *$'

# Frontmatter only, tolerating CRLF: fence 1 opens it, fence 2 ends the search.
has_regime() {                      # $1 SKILL.md
  [ -f "$1" ] || return 1
  awk '
    /^---\r?$/            { fences++; if (fences >= 2) exit; next }
    fences == 1 && /^disable-model-invocation: *true/ { found = 1; exit }
    END                   { exit (found ? 0 : 1) }
  ' "$1"
}

# Remove the frontmatter regime line in place, tolerating CRLF. Used by gen_patch so a patch owns
# only L1-L5 and not the line restore_regime re-inserts. No-op when the line is absent.
strip_regime() {                    # $1 SKILL.md  (edited in place)
  local f=$1 tmp
  [ -f "$f" ] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/skills-resync-strip-XXXXXX")
  awk '
    /^---\r?$/            { fences++; print; next }
    fences == 1 && /^disable-model-invocation: *true\r?$/ { next }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f" || rm -f "$tmp"
}

PY=$(command -v python3 || command -v python) || {
  echo "resync: needs python3 to read $PLUGINS_JSON" >&2; exit 1; }

# --- resolution --------------------------------------------------------------------------------
# The install cache under plugins/cache is NOT a usable upstream. These plugins are disabled, and
# `claude plugin update` is version-gated: it refuses to re-fetch a moved sha while plugin.json
# still names the same version, so a disabled plugin's cache is frozen at whatever it was installed
# with. Both sides of a cache comparison are then frozen and no drift is ever visible - which is
# the one failure this whole skill exists to prevent.
#
# The marketplace clone under plugins/marketplaces IS current: Claude Code refreshes it on startup
# and `claude plugin marketplace update` forces it. So upstream resolves marketplace-first, by the
# source kind the marketplace catalog records for the plugin:
#
#   "./plugins/<name>"          the plugin tree lives inside the marketplace clone   -> use it
#   {source: github, repo}      the marketplace clone *is* the plugin                -> use it
#   {source: url, url, sha}     content is not in the clone, only a pinned sha       -> mirror it
#
# Only the third kind needs anything fetched, and only when the pin has moved past the cache.
#
# The baseline column holds a hash of the upstream tree, not a plugin commit sha. A sha names the
# whole plugin, so any commit anywhere in it reads as "this skill moved"; a per-skill tree hash is
# exact, is comparable across all three source kinds, and needs no version directory or sha-length
# juggling. `--hash <dir>` prints one.
py_helper() { "$PY" - "$@" <<'PY'
import hashlib, json, os, sys

# Windows text mode turns every \n into \r\n, and the CR lands inside the last tab-separated field
# the shell reads - so an empty trailing field reads as non-empty and every row misclassifies.
try:
    sys.stdout.reconfigure(newline='\n')
except Exception:
    pass

def tree_hash(root):
    if not root or not os.path.isdir(root):
        return ''
    h = hashlib.sha256()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            p = os.path.join(dirpath, name)
            h.update(os.path.relpath(p, root).replace(os.sep, '/').encode() + b'\0')
            with open(p, 'rb') as fh:
                h.update(fh.read())
            h.update(b'\0')
    return h.hexdigest()[:16]

mode = sys.argv[1]
if mode == 'hash':
    print(tree_hash(sys.argv[2]))
    raise SystemExit(0)

inventory, plugins_json, marketplaces, mirrors = sys.argv[2:6]

def jload(path):
    try:
        with open(path, encoding='utf-8') as fh:
            return json.load(fh)
    except Exception:
        return {}

def same_sha(a, b):
    n = min(len(a), len(b))
    return n >= 7 and a[:n] == b[:n]

installed = jload(plugins_json).get('plugins', {})
_catalogs = {}

def catalog(marketplace):
    if marketplace not in _catalogs:
        doc = jload(os.path.join(marketplaces, marketplace, '.claude-plugin', 'marketplace.json'))
        entries = doc.get('plugins', doc) if isinstance(doc, dict) else doc
        _catalogs[marketplace] = {e.get('name'): e.get('source')
                                  for e in (entries or []) if isinstance(e, dict)}
    return _catalogs[marketplace]

def resolve(pid):
    """-> (plugin root, note, mirror-spec). root '' means unresolvable; note is 'state|detail'."""
    name, _, marketplace = pid.partition('@')
    entry = (installed.get(pid) or [{}])[0]
    cache_root, cache_sha = entry.get('installPath', ''), entry.get('gitCommitSha', '')
    src = catalog(marketplace).get(name)
    clone = os.path.join(marketplaces, marketplace)

    if isinstance(src, str):
        root = os.path.normpath(os.path.join(clone, src))
        if os.path.isdir(root):
            return root, '', None
    elif isinstance(src, dict) and src.get('source') == 'github' and os.path.isdir(clone):
        return clone, '', None
    elif isinstance(src, dict) and src.get('source') == 'url':
        pin, url = src.get('sha', ''), src.get('url', '')
        if pin and cache_sha and same_sha(pin, cache_sha) and os.path.isdir(cache_root):
            return cache_root, '', None            # the frozen cache happens to be current
        mirror = os.path.join(mirrors, pid, pin[:12]) if pin else ''
        spec = (pid, url, pin) if (pin and url) else None
        if mirror and os.path.isdir(mirror):
            return mirror, '', spec
        return '', 'refresh-needed|%s pins %s, install cache at %s - run --refresh' % (
            name, pin[:12] or '?', cache_sha[:12] or '?'), spec

    # No catalog entry: the marketplace was removed, or this is a scratch/self-test setup. The
    # install cache is the only thing left, and stale-but-present beats reporting nothing.
    if cache_root and os.path.isdir(cache_root):
        return cache_root, '', None
    return '', 'upstream-missing|%s: no marketplace entry and no install cache' % pid, None

rows, specs = [], []
for line in open(inventory, encoding='utf-8'):
    line = line.rstrip('\n')
    if not line.strip() or line.startswith('#'):
        continue
    f = line.split('\t')
    if len(f) < 4:
        continue
    skill, pid, sub, base = f[0], f[1], f[2], f[3]
    root, note, spec = resolve(pid)
    if spec and spec not in specs:
        specs.append(spec)
    up = os.path.join(root, sub) if root else ''
    if up and not os.path.isdir(up):
        up, note = '', 'upstream-missing|%s not present under %s' % (sub, root)
    # Forward slashes only: a mixed C:/a\b path is what os.path.join produces on Windows, and
    # cygpath silently mistranslates it.
    rows.append([skill, pid, sub, base, up.replace('\\', '/'), tree_hash(up), note])

if mode == 'mirrors':
    for pid, url, pin in specs:
        print('\t'.join([pid, url, pin]))
else:
    for r in rows:
        print('\t'.join(r))
PY
}

# Emits: skill \t plugin \t subpath \t baseline \t upstream-dir \t upstream-hash \t note
# upstream-dir is empty exactly when note is set. Paths come back native and are converted here,
# because MSYS mangles argv into Windows form on the way in but leaves stdout alone.
inventory_resolved() {
  local skill pid sub base up hash note
  py_helper resolve "$INVENTORY" "$PLUGINS_JSON" "$MARKETPLACES" "$MIRRORS" \
  | while IFS=$'\t' read -r skill pid sub base up hash note; do
      [ -n "$up" ] && up=$(cygpath -u "$up" 2>/dev/null || echo "$up")
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$skill" "$pid" "$sub" "$base" "$up" "$hash" "$note"
    done
}

lookup() {                          # $1 skill -> resolved row, or exit 1
  inventory_resolved | grep -P "^$1\t" || return 1
}

# Empty output means "no difference beyond the regime line". --strip-trailing-cr is mandatory:
# the locally-flagged skills were rewritten CRLF against LF upstream, and without it every line
# reads as changed - skill-creator shows 974 changed lines whose real content is one.
drift_diff() {                      # $1 upstream  $2 live
  diff -r --strip-trailing-cr -I "$REGIME_RE" "$1" "$2" 2>&1 || true
}

# --- refresh -----------------------------------------------------------------------------------
# Makes the current upstream content actually present on disk. Touches plugins/ only - nothing
# under $SKILLS_DIR is read or written here, so this runs before the user has confirmed anything.
refresh() {
  local pid url pin mirror
  if command -v claude >/dev/null 2>&1; then
    if claude plugin marketplace update >/dev/null 2>&1; then
      echo "refresh: marketplace clones updated"
    else
      echo "refresh: WARNING 'claude plugin marketplace update' failed - clones may be stale" >&2
    fi
  else
    echo "refresh: WARNING claude CLI not on PATH - marketplace clones not updated" >&2
  fi

  # A url-pinned plugin is the only kind whose current content is nowhere on disk: the catalog
  # records a sha, and the install cache is frozen behind it. Fetching the pinned commit shallow is
  # a couple of seconds and needs no plugin re-install, which would touch enabledPlugins.
  while IFS=$'\t' read -r pid url pin; do
    [ -n "$pid" ] || continue
    mirror="$MIRRORS/$pid/${pin:0:12}"
    if [ -d "$mirror/.git" ]; then
      echo "refresh: $pid already mirrored at ${pin:0:12}"; continue
    fi
    echo "refresh: mirroring $pid at ${pin:0:12}"
    rm -rf "$mirror"; mkdir -p "$mirror"
    if git init -q "$mirror" \
       && git -C "$mirror" remote add origin "$url" \
       && git -C "$mirror" fetch -q --depth 1 origin "$pin" \
       && git -C "$mirror" checkout -q FETCH_HEAD; then
      :
    else
      rm -rf "$mirror"
      echo "refresh: FAILED to mirror $pid at ${pin:0:12} from $url" >&2
    fi
  done < <(py_helper mirrors "$INVENTORY" "$PLUGINS_JSON" "$MARKETPLACES" "$MIRRORS")

  prune_mirrors
  echo "refresh: done - run --check"
}

# A mirror is resolved upstream, not a leftover, so the one at the currently pinned sha survives:
# --check and --diff need a tree to compare against on every later run, and re-fetching it on each
# invocation would put a network call in the middle of an inspection command. Every other mirror is
# dead the moment the pin moves, and goes.
prune_mirrors() {                   # $1 --dry-run to report only
  local dry=${1:-} keep d rel n=0
  [ -d "$MIRRORS" ] || return 0
  keep=$(py_helper mirrors "$INVENTORY" "$PLUGINS_JSON" "$MARKETPLACES" "$MIRRORS" \
         | awk -F'\t' 'NF>=3 {printf "%s/%s\n", $1, substr($3,1,12)}')
  while IFS= read -r d; do
    rel=${d#"$MIRRORS"/}
    if ! grep -qxF "$rel" <<<"$keep"; then
      n=$((n + 1)); [ -n "$dry" ] || rm -rf "$d"
    fi
  done < <(find "$MIRRORS" -mindepth 2 -maxdepth 2 -type d 2>/dev/null)
  [ "$n" -eq 0 ] || echo "clean: $n stale mirror(s)$([ -n "$dry" ] && echo ' (dry run)' || echo ' removed')"
  local live; live=$(grep -c . <<<"$keep" || true)
  [ "$live" -eq 0 ] || echo "clean: $live mirror(s) kept at the pinned sha (resolved upstream, not a leftover)"
}

# --- protected local edits as data ---------------------------------------------------------------
# SKILL.md's L1-L5 are line replacements against a known upstream text, so they are data, not prose:
# `patches/<skill>.patch` holds them and `patch` replays them onto a fresh vendor. That is what makes
# a re-vendor of an edited skill mechanical - previously it was a hand step no later check could see
# had been skipped, since a reverted edit reads as `identical` once the baseline is rebased.
#
# The patch is also the *only* record of which local edits exist. Once upstream moves, a diff no
# longer distinguishes a local edit from the upstream change, so every classification below treats
# "no patch" as "no local edits" and the REVIEW bucket exists to keep that true.
#
# A patch that no longer applies is the whole point: the reject names the exact line where upstream
# moved onto a local edit, which is the only case that ever needed judgement.
patch_file() { echo "$PATCHES/$1.patch"; }

# Staged as a/ and b/ so headers are `a/SKILL.md` and `b/SKILL.md` and `patch -p1` is unambiguous -
# diffing the real paths leaves patch guessing the strip depth from an absolute path.
# --strip-trailing-cr is what lets a CRLF live file patch a LF upstream; -N carries added files
# (L4's code-reviewer.md is a whole file that exists only locally).
#
# The mtime is stripped from the ---/+++ headers: the staged copies are fresh every run, so leaving
# it in makes the patch text differ on every generation and the staleness check below cry wolf
# forever. Without it the patch is a stable artifact that only changes when an edit does.
gen_patch() {                       # $1 upstream  $2 live -> patch on stdout
  local t; t=$(mktemp -d "${TMPDIR:-/tmp}/skills-resync-gen-XXXXXX")
  cp -r "$1" "$t/a"; cp -r "$2" "$t/b"
  # L6 has exactly one owner, restore_regime. Leaving it in the patch too makes apply insert it
  # twice: restore_regime writes the line, then the patch hunk finds its own change already there
  # and rejects the whole file - which reads as "upstream moved onto a protected edit" and rolls
  # back a re-vendor that was perfectly applicable. Strip it here so the patch owns only L1-L5.
  [ -f "$t/b/SKILL.md" ] && strip_regime "$t/b/SKILL.md"
  ( cd "$t" && diff -ruN --strip-trailing-cr a b ) \
    | sed -E 's/^(---|\+\+\+) ([^\t]*)\t.*/\1 \2/' || true
  rm -rf "$t"
}

# --no-backup-if-mismatch keeps .orig files out of $SKILLS_DIR; rejects still land as .rej and are
# swept by clean(). Returns non-zero on any reject so the caller can roll back.
replay_patch() {                    # $1 skill  $2 live-dir
  local pf; pf=$(patch_file "$1")
  [ -f "$pf" ] || return 0
  patch -p1 -s --no-backup-if-mismatch -d "$2" < "$pf"
}

# --- check -------------------------------------------------------------------------------------
# Two inputs decide the state jointly: the upstream tree hash against the baseline says whether
# upstream moved, the diff says what a re-vendor would change. Never infer either from diff size.
check() {
  local skill pid sub base up hash note state d n r pf
  local appliable='' review='' blocked='' stale='' regimes=0
  printf '%-32s %-6s %s\n' SKILL REGIME 'STATE / DETAIL'
  while IFS=$'\t' read -r skill pid sub base up hash note; do
    pf=$(patch_file "$skill")
    # The diff ignores the regime line, so report it separately: without this a skill that lost
    # its L6 flag out of band would read as identical, which is the one failure this whole skill
    # exists to catch. Reported, not asserted - a deliberate promotion needs no bookkeeping.
    if has_regime "$SKILLS_DIR/$skill/SKILL.md" 2>/dev/null; then
      r='slash'; regimes=$((regimes + 1))
    else
      r='-'
    fi
    if [ ! -d "$SKILLS_DIR/$skill" ]; then
      state=not-vendored; d="no $SKILLS_DIR/$skill"
    elif [ -n "$note" ]; then
      state=${note%%|*}; d=${note#*|}
    else
      n=$(drift_diff "$up" "$SKILLS_DIR/$skill" | grep -c . || true)
      if [ "$base" = "$hash" ]; then
        if [ "$n" -eq 0 ]; then
          state=identical; d=''
        elif [ ! -f "$pf" ]; then
          # Upstream is at the baseline, so this diff is unambiguously a local edit - and this is
          # the only window in which it is. Capture it now or the next upstream move eats it.
          state=unsnapshotted; d="$n diff lines, no patch - run --snapshot $skill"
        elif [ -n "$(diff -q <(gen_patch "$up" "$SKILLS_DIR/$skill") "$pf" 2>&1)" ]; then
          state=patch-stale;  d="local edits changed since snapshot - re-run --snapshot $skill"
        else
          state=local-only;   d="$n diff lines, upstream at baseline, patch current"
        fi
      else
        # Upstream moved. The patch is the record of local edits, so its absence means there are
        # none and the whole diff is upstream's - an unedited skill with a moved upstream is the
        # mainline update, and must be appliable rather than held back as ambiguous.
        state=upstream-changed
        if [ -f "$pf" ]; then
          d="upstream $base -> $hash, $n diff lines, local patch will replay"
        else
          d="upstream $base -> $hash, $n diff lines to take"
        fi
      fi
    fi
    printf '%-32s %-6s %s\n' "$skill" "$r" "$state${d:+  $d}"
    case $state in
      upstream-changed)            appliable+=" $skill" ;;
      unsnapshotted|patch-stale)   review+=" $skill" ;;
      refresh-needed)              stale+=" $skill" ;;
      identical|local-only)        ;;
      *)                           blocked+=" $skill" ;;
    esac
  done < <(inventory_resolved)

  # local-only with a current patch is healthy and silent: the edit is captured, so a later
  # re-vendor replays it. REVIEW now means only "an edit exists that a re-vendor would lose".
  echo
  echo "APPLIABLE:${appliable:- none}      # --apply these after one confirmation"
  echo "REVIEW:${review:- none}      # local edits not captured in a patch - --snapshot them"
  echo "REFRESH:${stale:- none}      # upstream not on disk - run --refresh, then --check again"
  echo "BLOCKED:${blocked:- none}      # not vendored, or upstream gone"
  local unmapped
  unmapped=$(comm -23 \
    <(cd "$SKILLS_DIR" && ls -d */ 2>/dev/null | tr -d /  | sort) \
    <(cut -f1 "$INVENTORY" | grep -v '^#' | grep . | sort))
  echo "UNMAPPED: $(echo $unmapped)   # expected: the originals with no upstream"
  echo "REGIME: $regimes of $(grep -cvE '^#|^$' "$INVENTORY") mapped skills are slash-only" \
       "(+ $(echo $unmapped | wc -w) unmapped) - reconcile against SKILL.md L6"
}

# --- apply -------------------------------------------------------------------------------------
# Stage, verify, back up, swap. Nothing under $SKILLS_DIR is touched until a verified copy exists,
# so a failed copy can never leave a skill half-written. Replacement is wholesale, not a merge: a
# stale file left behind by an upstream deletion is drift no later diff would catch.
apply_one() {                       # $1 skill  $2 upstream  $3 work
  local skill=$1 up=$2 work=$3
  local live="$SKILLS_DIR/$skill" stage="$work/stage/$skill" backup="$work/backup/$skill" regime=no patched=''

  [ -d "$up" ]   || { echo "  $skill: upstream missing ($up)" >&2; return 1; }
  [ -d "$live" ] || { echo "  $skill: not vendored locally ($live)" >&2; return 1; }

  # `grep && regime=yes` would return non-zero for a skill with no regime line, which under set -e
  # aborts apply_one before it stages anything whenever it is called outside a condition.
  if has_regime "$live/SKILL.md" 2>/dev/null; then regime=yes; fi

  rm -rf "$work/stage" "$work/backup"; mkdir -p "$work/stage" "$work/backup"
  cp -r "$up" "$stage"
  # A copy must be byte-identical - no --strip-trailing-cr here, or a mangled copy verifies clean.
  if ! diff -rq "$up" "$stage" >/dev/null; then
    echo "  $skill: staged copy does not match upstream, nothing changed" >&2; return 1
  fi

  mv "$live" "$backup"
  if ! mv "$stage" "$live"; then
    mv "$backup" "$live"
    echo "  $skill: swap failed, original restored" >&2; return 1
  fi

  if [ "$regime" = yes ] && ! has_regime "$live/SKILL.md"; then
    restore_regime "$live/SKILL.md" || { echo "  $skill: WARNING regime line not restored" >&2; }
  fi

  # Replay the protected edits. A reject means upstream rewrote a line the local edit owns - the
  # one case that needs judgement - so restore the backup wholesale rather than leave a half-edited
  # skill and a .rej file for someone to find later.
  if [ -f "$(patch_file "$skill")" ]; then
    # patch reports rejects on stdout, so both streams go to the log or the reason is lost.
    if replay_patch "$skill" "$live" >"$work/patch.err" 2>&1; then
      patched=' +patch'
    else
      rm -rf "$live"; mv "$backup" "$live"
      echo "  $skill: local patch rejected, ROLLED BACK to the pre-apply copy" >&2
      sed 's/^/    /' "$work/patch.err" >&2
      echo "    upstream moved onto a protected edit - reconcile by hand, then --snapshot" >&2
      return 1
    fi
  fi

  # Post-condition: the live tree must be exactly upstream plus the protected edits. `patch` can
  # succeed with fuzz and place an edit on the wrong line, and a duplicated regime line applies
  # cleanly too - both read as success everywhere else. Checked here, while the backup still exists,
  # so exiting 0 means verified rather than merely attempted.
  if ! verify_patch "$skill" "$up"; then
    rm -rf "$live"; mv "$backup" "$live"
    echo "  $skill: post-apply tree does not match upstream+patch, ROLLED BACK" >&2; return 1
  fi
  echo "  $skill: written$([ "$regime" = yes ] && echo ' +regime')$patched +verified" >&2
}

# Re-insert L6 before the closing frontmatter fence. Tolerates CRLF, and refuses a file with no
# frontmatter rather than writing the line into the body where it would be inert.
restore_regime() {                  # $1 SKILL.md
  local f=$1 out="$1.regime"
  awk -v line="$REGIME" '
    /^---\r?$/ { fences++; if (fences == 2) print line; print; next }
    { print }
    END { exit (fences >= 2 ? 0 : 1) }
  ' "$f" > "$out" || { rm -f "$out"; return 1; }
  mv "$out" "$f"
}

# Rebase the inventory in the same pass as the write. Left for later it never happens, and the next
# run then reports every one of these skills as upstream-changed and re-vendors them again.
rebase_baselines() {                # $@ skill=hash
  [ $# -gt 0 ] || return 0
  "$PY" - "$INVENTORY" "$@" <<'PY'
import sys
inv, pairs = sys.argv[1], dict(a.split('=', 1) for a in sys.argv[2:])
out = []
for line in open(inv, encoding='utf-8').read().splitlines(True):
    f = line.rstrip('\n').split('\t')
    if len(f) == 4 and f[0] in pairs:
        f[3] = pairs[f[0]]
        line = '\t'.join(f) + '\n'
    out.append(line)
open(inv, 'w', encoding='utf-8', newline='\n').writelines(out)
PY
}

apply() {
  local work written=0 failed=0 rebase=() skill row base up hash note
  work=$(mktemp -d "${TMPDIR:-/tmp}/skills-resync-work-XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT        # fires on success, failure and interrupt alike

  for skill in "$@"; do
    if ! row=$(lookup "$skill"); then
      echo "  $skill: not in inventory.tsv" >&2; failed=$((failed + 1)); continue
    fi
    base=$(cut -f4 <<<"$row"); up=$(cut -f5 <<<"$row")
    hash=$(cut -f6 <<<"$row"); note=$(cut -f7 <<<"$row")
    if [ -n "$note" ]; then
      echo "  $skill: ${note%%|*} - ${note#*|}" >&2; failed=$((failed + 1)); continue
    fi
    # Interlock: an unsnapshotted local edit is the one thing the swap destroys with no way to
    # replay it - and it is only *detectable* while upstream still sits at the baseline. Refuse
    # exactly that case. Comparing against a moved upstream instead would read the upstream change
    # itself as an uncaptured edit and refuse every unedited skill, which is the mainline update.
    if [ "$base" = "$hash" ] && [ ! -f "$(patch_file "$skill")" ] \
       && [ -n "$(drift_diff "$up" "$SKILLS_DIR/$skill")" ]; then
      echo "  $skill: refused - uncaptured local edits (run --snapshot $skill first)" >&2
      failed=$((failed + 1)); continue
    fi
    if apply_one "$skill" "$up" "$work"; then
      written=$((written + 1)); rebase+=("$skill=$hash")
    else
      failed=$((failed + 1))
    fi
  done

  # Only successful writes rebase: a rolled-back skill keeps its old baseline so the next --check
  # still reports it as needing attention.
  rebase_baselines "${rebase[@]+"${rebase[@]}"}"
  clean
  echo "written=$written failed=$failed baselines_rebased=${#rebase[@]}"
  [ "$written" -eq 0 ] \
    || echo "Regime line and protected edits replayed and verified against upstream+patch."
  [ "$failed" -eq 0 ] \
    || echo "Rolled-back skills keep their old baseline, so --check still reports them."
  [ "$failed" -eq 0 ]
}

# --- snapshot -------------------------------------------------------------------------------
# Capture a skill's current local edits as the patch a later re-vendor replays. Refuses while
# upstream is off-baseline: the diff there mixes the local edit with the upstream change, and
# snapshotting it would bake an upstream revert into the patch permanently.
snapshot() {
  local skill row up base hash note n; local rc=0
  mkdir -p "$PATCHES"
  for skill in "$@"; do
    if ! row=$(lookup "$skill"); then
      echo "  $skill: not in inventory.tsv" >&2; rc=1; continue
    fi
    base=$(cut -f4 <<<"$row"); up=$(cut -f5 <<<"$row")
    hash=$(cut -f6 <<<"$row"); note=$(cut -f7 <<<"$row")
    if [ -n "$note" ]; then
      echo "  $skill: ${note%%|*} - ${note#*|}" >&2; rc=1; continue
    fi
    if [ "$base" != "$hash" ]; then
      echo "  $skill: refused - upstream moved to $hash; reconcile by hand first" >&2
      rc=1; continue
    fi
    if [ -z "$(drift_diff "$up" "$SKILLS_DIR/$skill")" ]; then
      rm -f "$(patch_file "$skill")"
      echo "  $skill: no local edits, patch removed"; continue
    fi
    gen_patch "$up" "$SKILLS_DIR/$skill" > "$(patch_file "$skill")"
    # Prove it replays before trusting it: a patch that does not reproduce the live tree is worse
    # than none, because --check would then read the skill as protected when it is not.
    if verify_patch "$skill" "$up"; then
      n=$(grep -c . "$(patch_file "$skill")" || true)
      echo "  $skill: snapshot written ($n lines), replay verified"
    else
      rm -f "$(patch_file "$skill")"
      echo "  $skill: snapshot did NOT replay cleanly, discarded" >&2; rc=1
    fi
  done
  return $rc
}

# Copy upstream, replay the patch, and require the result to equal the live tree.
verify_patch() {                    # $1 skill  $2 upstream
  local t ok=0; t=$(mktemp -d "${TMPDIR:-/tmp}/skills-resync-vfy-XXXXXX")
  cp -r "$2" "$t/x"
  replay_patch "$1" "$t/x" >/dev/null 2>&1 \
    && [ -z "$(diff -r --strip-trailing-cr -I "$REGIME_RE" "$t/x" "$SKILLS_DIR/$1")" ] || ok=1
  rm -rf "$t"
  return $ok
}

# --- cleanup ----------------------------------------------------------------------------------
# Everything a resync run can leave behind, plus the marketplace clones the plugin installer
# orphans at cache/temp_git_*. Runs unattended at the end of every --apply.
#
# The globs name this script's own three temp prefixes rather than skills-resync-* : the self-test
# root is a skills-resync-test-* directory, and a wildcard would have --apply delete the test it is
# running under.
#
# An orphan younger than ORPHAN_MIN_AGE minutes is left alone and reported: a concurrent plugin
# install does its work inside one of these, and a resync cannot tell a live clone from a corpse
# by name. Age is the knob - lower it when sweeping a machine known to be idle.
ORPHAN_MIN_AGE="${ORPHAN_MIN_AGE:-60}"

clean() {                           # $1 --dry-run to report only
  local dry=${1:-} p targets=() young=0
  for p in "${TMPDIR:-/tmp}"/skills-resync-work-* "${TMPDIR:-/tmp}"/skills-resync-gen-* \
           "${TMPDIR:-/tmp}"/skills-resync-vfy-* "${TMPDIR:-/tmp}"/skills-resync-strip-* \
           /skills-resync-backup; do
    [ -e "$p" ] && targets+=("$p")
  done
  # .regime sits at depth 2; patch rejects land beside the file they failed on, which for a
  # references/*.md edit is depth 3. Sweep to 4 so no nesting outruns this.
  while IFS= read -r p; do targets+=("$p"); done \
    < <(find "$SKILLS_DIR" -maxdepth 4 \( -name '*.regime' -o -name '*.rej' -o -name '*.orig' \) 2>/dev/null)
  while IFS= read -r p; do targets+=("$p"); done \
    < <(find "$PLUGIN_CACHE" -maxdepth 1 -name 'temp_git_*' -mmin +"$ORPHAN_MIN_AGE" 2>/dev/null)
  young=$(find "$PLUGIN_CACHE" -maxdepth 1 -name 'temp_git_*' -mmin -"$ORPHAN_MIN_AGE" 2>/dev/null | grep -c . || true)

  [ "$young" -eq 0 ] || echo "clean: $young temp_git_* younger than ${ORPHAN_MIN_AGE}m kept (may be in use)"
  if [ ${#targets[@]} -gt 0 ]; then
    du -sh "${targets[@]}" 2>/dev/null || true
    echo "clean: ${#targets[@]} leftover path(s)$([ -n "$dry" ] && echo ' (dry run, nothing removed)')"
    [ -n "$dry" ] || { rm -rf "${targets[@]}"; echo "clean: removed"; }
  else
    echo "clean: no backup or temp leftovers"
  fi
  prune_mirrors "$dry"
}

# --- self-test --------------------------------------------------------------------------------
self_test() {
  local root; root=$(mktemp -d "${TMPDIR:-/tmp}/skills-resync-test-XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -rf '$root'" RETURN
  # Every path the tested code sweeps or reads has to point inside the scratch root, or a self-test
  # that reaches apply() would clean the real plugin cache and mirrors on its way through.
  PLUGIN_CACHE="$root/cache"; MIRRORS="$root/mirrors"; MARKETPLACES="$root/marketplaces"
  mkdir -p "$PLUGIN_CACHE"

  mkdir -p "$root/up/demo" "$root/skills/demo" "$root/work"
  printf -- '---\nname: demo\n---\nnew\n' > "$root/up/demo/SKILL.md"
  printf -- '---\nname: demo\ndisable-model-invocation: true\n---\nold\n' > "$root/skills/demo/SKILL.md"
  printf 'stale\n' > "$root/skills/demo/dropped-upstream.md"

  SKILLS_DIR="$root/skills"
  INVENTORY="$root/inventory.tsv"
  PATCHES="$root/patches"; mkdir -p "$PATCHES"
  printf 'demo\tp@m\tskills/demo\tOLDHASH123456\n' > "$INVENTORY"

  apply_one demo "$root/up/demo" "$root/work" 2>/dev/null
  grep -q '^new$' "$root/skills/demo/SKILL.md" \
    || { echo "self-test FAIL: content not replaced" >&2; return 1; }
  [ ! -e "$root/skills/demo/dropped-upstream.md" ] \
    || { echo "self-test FAIL: file deleted upstream survived locally" >&2; return 1; }
  [ -f "$root/work/backup/demo/SKILL.md" ] \
    || { echo "self-test FAIL: no backup taken" >&2; return 1; }
  [ "$(sed -n 3p "$root/skills/demo/SKILL.md")" = "$REGIME" ] \
    || { echo "self-test FAIL: regime line not restored inside frontmatter" >&2; return 1; }
  [ -z "$(drift_diff "$root/up/demo" "$root/skills/demo")" ] \
    || { echo "self-test FAIL: regime-only diff not ignored" >&2; return 1; }

  rebase_baselines demo=NEWHASH654321
  grep -q $'demo\tp@m\tskills/demo\tNEWHASH654321' "$INVENTORY" \
    || { echo "self-test FAIL: baseline not rebased" >&2; return 1; }

  # A missing upstream must leave the live copy untouched.
  printf 'keep\n' > "$root/skills/demo/SKILL.md"
  if apply_one demo "$root/up/absent" "$root/work" 2>/dev/null; then
    echo "self-test FAIL: missing upstream reported success" >&2; return 1
  fi
  [ "$(cat "$root/skills/demo/SKILL.md")" = keep ] \
    || { echo "self-test FAIL: live copy touched despite missing upstream" >&2; return 1; }

  # A body-only file must be refused rather than have the line written into prose.
  printf 'no frontmatter\n' > "$root/skills/demo/SKILL.md"
  if restore_regime "$root/skills/demo/SKILL.md" 2>/dev/null; then
    echo "self-test FAIL: regime line written into a file with no frontmatter" >&2; return 1
  fi
  [ ! -e "$root/skills/demo/SKILL.md.regime" ] \
    || { echo "self-test FAIL: temp file left behind" >&2; return 1; }

  # --- the tree hash is what the baseline compares on -------------------------------------------
  [ "$(py_helper hash "$root/up/demo")" = "$(py_helper hash "$root/up/demo")" ] \
    || { echo "self-test FAIL: tree hash not stable" >&2; return 1; }
  printf 'x\n' > "$root/up/demo/extra.md"
  [ "$(py_helper hash "$root/up/demo")" != "$(py_helper hash "$root/skills/demo")" ] \
    || { echo "self-test FAIL: tree hash blind to an added file" >&2; return 1; }
  rm -f "$root/up/demo/extra.md"

  # --- protected edits replay across a re-vendor ------------------------------------------------
  # A local edit on a line upstream does not touch: the patch must carry it onto the new vendor.
  mkdir -p "$root/up2/demo" "$root/skills2/demo" "$root/work2" "$root/patches2"
  SKILLS_DIR="$root/skills2"; PATCHES="$root/patches2"
  # The two edits sit >3 lines apart so they land in separate hunks - adjacent ones would share
  # context lines and reject, which is the behaviour the rollback case below covers instead.
  # The local copy also carries L6, so this doubles as the regression guard for the two-owner bug:
  # restore_regime inserts the line, and if gen_patch had left it in the patch as well the replay
  # would find its own change already applied and reject a perfectly appliable re-vendor.
  demo_body() {                     # $1 first line  $2 last line  $3 non-empty for the regime line
    printf -- '---\nname: demo\n%s---\n%s\np\nq\nr\ns\nt\nu\n%s\n' "${3:+$REGIME$'\n'}" "$1" "$2"; }
  demo_body keep-me    tail-v1     > "$root/up2/demo/SKILL.md"
  demo_body LOCAL-EDIT tail-v1 yes > "$root/skills2/demo/SKILL.md"
  gen_patch "$root/up2/demo" "$root/skills2/demo" > "$PATCHES/demo.patch"
  verify_patch demo "$root/up2/demo" \
    || { echo "self-test FAIL: fresh snapshot does not replay" >&2; return 1; }

  demo_body keep-me tail-v2 > "$root/up2/demo/SKILL.md"
  apply_one demo "$root/up2/demo" "$root/work2" 2>/dev/null \
    || { echo "self-test FAIL: apply with a replayable patch failed" >&2; return 1; }
  grep -q '^LOCAL-EDIT$' "$root/skills2/demo/SKILL.md" \
    || { echo "self-test FAIL: protected edit lost across re-vendor" >&2; return 1; }
  grep -q '^tail-v2$' "$root/skills2/demo/SKILL.md" \
    || { echo "self-test FAIL: upstream change not taken" >&2; return 1; }
  [ "$(grep -c "^$REGIME\$" "$root/skills2/demo/SKILL.md")" = 1 ] \
    || { echo "self-test FAIL: regime line missing or duplicated alongside a patch" >&2; return 1; }
  grep -q 'disable-model-invocation' "$PATCHES/demo.patch" \
    && { echo "self-test FAIL: regime line leaked into the patch" >&2; return 1; }

  # --- a reject rolls back whole ----------------------------------------------------------------
  # Upstream rewrites the very line the patch owns. Nothing may be left half-applied.
  mkdir -p "$root/up3/demo" "$root/skills3/demo" "$root/work3" "$root/patches3"
  SKILLS_DIR="$root/skills3"; PATCHES="$root/patches3"
  printf -- '---\nname: demo\n---\na\nb\nc\nd\ne\nf\ng\n' > "$root/up3/demo/SKILL.md"
  printf -- '---\nname: demo\n---\na\nb\nc\nLOCAL\ne\nf\ng\n' > "$root/skills3/demo/SKILL.md"
  gen_patch "$root/up3/demo" "$root/skills3/demo" > "$PATCHES/demo.patch"
  printf -- '---\nname: demo\n---\nQ\nR\nS\nT\nU\nV\nW\n' > "$root/up3/demo/SKILL.md"
  if apply_one demo "$root/up3/demo" "$root/work3" 2>/dev/null; then
    echo "self-test FAIL: rejected patch reported success" >&2; return 1
  fi
  grep -q '^LOCAL$' "$root/skills3/demo/SKILL.md" \
    || { echo "self-test FAIL: rollback did not restore the local edit" >&2; return 1; }
  grep -q '^Q$' "$root/skills3/demo/SKILL.md" \
    && { echo "self-test FAIL: rollback left upstream content behind" >&2; return 1; }
  [ -z "$(find "$root/skills3" -name '*.rej' -o -name '*.orig' | grep . || true)" ] \
    || { echo "self-test FAIL: reject/backup files left in place" >&2; return 1; }

  # --- the mainline update: unedited skill, upstream moved --------------------------------------
  # The regression this guards is the one that made the whole skill inert. Classification and the
  # apply interlock both compared the live copy against the *moved* upstream, so the upstream change
  # itself read as an uncaptured local edit: every unedited skill came out BLOCKED and was refused.
  # Driven through check() and apply() rather than apply_one, because that is where the bug lived.
  mkdir -p "$root/up4/p/skills/demo" "$root/skills4/demo" "$root/patches4"
  SKILLS_DIR="$root/skills4"; PATCHES="$root/patches4"; INVENTORY="$root/inv4.tsv"
  PLUGINS_JSON="$root/plugins4.json"
  printf -- '---\nname: demo\n---\nUPSTREAM-v2\n' > "$root/up4/p/skills/demo/SKILL.md"
  printf -- '---\nname: demo\n---\nupstream-v1\n' > "$root/skills4/demo/SKILL.md"
  "$PY" -c 'import json,sys; json.dump({"plugins":{"p@m":[{"installPath":sys.argv[1],
            "gitCommitSha":"deadbeefdeadbeef"}]}}, open(sys.argv[2],"w"))' \
       "$root/up4/p" "$PLUGINS_JSON"
  printf 'demo\tp@m\tskills/demo\t0000000000000000\n' > "$INVENTORY"
  # Captured, not piped into grep -q: under pipefail an early-exiting grep SIGPIPEs check and the
  # pipeline reports 141 however the assertion actually turned out.
  case "$(check)" in *'APPLIABLE: demo'*) ;;
    *) echo "self-test FAIL: unedited skill with a moved upstream is not APPLIABLE" >&2; return 1 ;;
  esac
  apply demo >/dev/null 2>&1 \
    || { echo "self-test FAIL: apply refused an unedited skill with a moved upstream" >&2; return 1; }
  grep -q '^UPSTREAM-v2$' "$root/skills4/demo/SKILL.md" \
    || { echo "self-test FAIL: upstream update not taken" >&2; return 1; }
  [ "$(cut -f4 "$INVENTORY")" = "$(py_helper hash "$root/up4/p/skills/demo")" ] \
    || { echo "self-test FAIL: baseline not rebased to the upstream tree hash" >&2; return 1; }
  case "$(check)" in *'identical'*) ;;
    *) echo "self-test FAIL: re-check after apply does not read identical" >&2; return 1 ;;
  esac
  [ -d "$root" ] \
    || { echo "self-test FAIL: apply's clean deleted the scratch root" >&2; return 1; }

  # An uncaptured local edit is still refused - upstream sits at the baseline, so it is detectable.
  printf -- '---\nname: demo\n---\nHAND-EDIT\n' > "$root/skills4/demo/SKILL.md"
  if apply demo >/dev/null 2>&1; then
    echo "self-test FAIL: apply overwrote an uncaptured local edit" >&2; return 1
  fi
  grep -q '^HAND-EDIT$' "$root/skills4/demo/SKILL.md" \
    || { echo "self-test FAIL: refused apply still touched the live copy" >&2; return 1; }

  # --- a body prose mention must not read as the frontmatter flag ------------------------------
  # The regression: claude-automation-recommender documents `disable-model-invocation: true` in its
  # body. An unanchored whole-file grep matched that line, so restore_regime was skipped and the
  # skill got silently promoted to model-invoked. has_regime scopes to the frontmatter; this checks
  # both it and the apply path that depends on it. Temps live under $root so the RETURN trap reaps
  # them - a real /tmp mktemp here would leak, since clean() never runs in the self-test.
  local doc="$root/doc-neg" doc2="$root/doc-pos"
  printf -- '---\nname: demo\n---\nbody\nSet disable-model-invocation: true  # for user-only\n' > "$doc"
  has_regime "$doc" \
    && { echo "self-test FAIL: body prose mention read as a frontmatter regime flag" >&2; return 1; }
  # And the positive control: the same line in the frontmatter does count.
  printf -- '---\nname: demo\ndisable-model-invocation: true\n---\nbody\n' > "$doc2"
  has_regime "$doc2" \
    || { echo "self-test FAIL: frontmatter regime flag not detected" >&2; return 1; }

  # End-to-end: a slash-only skill whose upstream *documents* the flag in prose must be re-flagged
  # after a re-vendor, not silently promoted by the body mention.
  mkdir -p "$root/up5/demo" "$root/skills5/demo" "$root/work5"
  SKILLS_DIR="$root/skills5"
  printf -- '---\nname: demo\n---\nv1\nSet disable-model-invocation: true  # example\n' > "$root/up5/demo/SKILL.md"
  awk -v line="$REGIME" '
    /^---\r?$/ { fences++; if (fences == 2) print line; print; next }
    { print }
  ' "$root/up5/demo/SKILL.md" > "$root/skills5/demo/SKILL.md"
  apply_one demo "$root/up5/demo" "$root/work5" 2>/dev/null \
    || { echo "self-test FAIL: apply of a body-mention skill failed" >&2; return 1; }
  has_regime "$root/skills5/demo/SKILL.md" \
    || { echo "self-test FAIL: regime flag lost on a skill that documents it in prose" >&2; return 1; }
  [ "$(awk '/^---\r?$/{f++} f==1&&/^disable-model-invocation/{c++} END{print c}' "$root/skills5/demo/SKILL.md")" = 1 ] \
    || { echo "self-test FAIL: regime flag duplicated after restore" >&2; return 1; }

  echo "self-test OK"
}

usage() { sed -n '/^# Usage:/,/^set -/p' "${BASH_SOURCE[0]}" | sed -n 's/^# \?//p'; }

case "${1:---help}" in
  --refresh)   refresh ;;
  --check)     check ;;
  --diff)      [ $# -eq 2 ] || { usage; exit 2; }
               row=$(lookup "$2") || { echo "$2: not in inventory.tsv" >&2; exit 1; }
               up=$(cut -f5 <<<"$row"); note=$(cut -f7 <<<"$row")
               [ -z "$note" ] || { echo "$2: ${note%%|*} - ${note#*|}" >&2; exit 1; }
               drift_diff "$up" "$SKILLS_DIR/$2" ;;
  --snapshot)  shift; [ $# -gt 0 ] || { usage; exit 2; }; snapshot "$@" ;;
  --apply)     shift; [ $# -gt 0 ] || { usage; exit 2; }; apply "$@" ;;
  --hash)      [ $# -eq 2 ] || { usage; exit 2; }; py_helper hash "$2" ;;
  --clean)     clean "${2:-}" ;;
  --self-test) self_test ;;
  -h|--help)   usage ;;
  *)           usage; exit 2 ;;
esac
