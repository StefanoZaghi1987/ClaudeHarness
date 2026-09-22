#!/usr/bin/env bash
# Mechanical half of skills-resync: resolve upstream, classify drift, re-vendor, clean up.
# Judgement stays in this skill's documents - SKILL.md carries the procedure and the L-flag
# index, RULINGS.md the full rulings: which protected edits a skill carries, and whether a
# remaining diff is one of them. Everything this script does is decidable without reading prose.
#
# Usage: resync.sh --refresh                    pull marketplaces, sync mirrors (pinned sha, git branch)
#        resync.sh --check                      classify every skill in inventory.tsv
#        resync.sh --lint                       report reference candidates between skills (paths, dispatches)
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
# One anchor for every "beside the script" path - the INVENTORY/PATCHES defaults and the
# flat-layout guard in check() - so the three cannot drift apart.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
INVENTORY="${INVENTORY:-$SCRIPT_DIR/inventory.tsv}"
PATCHES="${PATCHES:-$SCRIPT_DIR/patches}"

# L6 (regime ledger in RULINGS.md): local invocation regime, never upstream state. The script owns re-applying it
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
# if a body line ever appears in exactly this form. One predicate, three encodings: this filter,
# has_regime above, slash_only in lint's python - change them together.
REGIME_RE='^disable-model-invocation: *true *$'

# Record separator for every resolved row on the wire. It has to be a non-whitespace character:
# see the note in py_helper's output block - tab collapses empty fields and silently shifts a row.
US=$'\x1f'

# Frontmatter only, tolerating CRLF: fence 1 opens it, fence 2 ends the search. One predicate,
# three encodings: this awk (reference semantics), REGIME_RE below (diff filter, fully anchored
# by design) and slash_only in lint's python - change them together.
has_regime() {                      # $1 SKILL.md
  [ -f "$1" ] || return 1
  awk '
    /^---\r?$/            { fences++; if (fences >= 2) exit; next }
    fences == 1 && /^disable-model-invocation: *true/ { found = 1; exit }
    END                   { exit (found ? 0 : 1) }
  ' "$1"
}

# Remove the frontmatter regime line in place, tolerating CRLF. Used by gen_patch so a patch owns
# only the protected edits and not the line restore_regime re-inserts. No-op when the line is absent.
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
# A pid starting `git+` never reaches the catalog at all: it is a plain repo tracked at a branch
# (git+<repo>@<branch>), the inventory row is the whole spec, and its mirror at the branch tip is
# mutable - sync_mirrors fetches and hard-resets it every run, where a pinned-sha mirror is skipped.
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

# ponytail: the mirror path must stay exactly two segments under $MIRRORS - prune_mirrors' depth-2
# sweep rm -rf's exactly what it finds there, so any future pid grammar with an unmunged separator
# would reintroduce a mid-tree delete, and on Windows an unmunged backslash escapes $MIRRORS
# outright (a joined component with a drive root resets the path). The colon is the third such
# character: legal inside a git+ drive path (D:/repo), illegal inside a Windows directory
# component, so unmunged it names a mirror no mkdir can create. Hash-suffix the pid here if a
# second repo ever collides with a munged name.
def munge(s):
    return s.replace('/', '__').replace('\\', '__').replace(':', '__')

def resolve(pid):
    """-> (plugin root, note, mirror-spec). root '' means unresolvable; note is 'state|detail'."""
    # git+<repo>@<branch>: a plain repo, no marketplace - the row itself is the spec and the branch
    # tip is the upstream. rpartition, not partition: the repo may contain slashes, the branch is
    # the last field.
    if pid.startswith('git+'):
        repo, _, branch = pid[4:].rpartition('@')
        if not repo or not branch:
            return '', 'upstream-missing|malformed git pid %s' % pid, None
        # A Windows drive path (D:/repo) is absolute too - prefixing it would fabricate
        # https://D:/repo, which no fetch can reach. repo[1]==':' is the drive-colon test.
        absolute = repo.startswith('/') or (len(repo) >= 2 and repo[1] == ':')
        # scp-like git@host:path and its colonless twin user@host/path: no scheme with a user
        # part. https-prefixed, the colon form lands the path in the (invalid) port slot and the
        # colonless form only ever waits on a credential prompt - either way nothing fetches
        # unattended, sync_mirrors retries forever and the row sits REFRESH for good. Same verdict
        # as a branchless pid: malformed, spec None, so nothing ever fetches. Drive-absolute is
        # tested first: D:/a@b is a path, not a user.
        if not absolute and '://' not in repo and '@' in repo:
            return '', 'upstream-missing|malformed git pid %s' % pid, None
        url = repo if (absolute or '://' in repo) else 'https://' + repo
        rel = munge('git+' + repo) + '/' + munge(branch)
        mirror = os.path.join(mirrors, *rel.split('/'))
        spec = (pid, url, branch, rel, 'git')
        if os.path.isdir(mirror):
            return mirror, '', spec
        return '', 'refresh-needed|%s branch %s not mirrored - run --refresh' % (repo, branch), spec
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
        mirror = os.path.join(mirrors, munge(pid), pin[:12]) if pin else ''
        spec = (pid, url, pin, munge(pid) + '/' + pin[:12], 'sha') if (pin and url) else None
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
    # Optional 5th column: where the vendored copy lives, relative to $SKILLS_DIR. Empty means the
    # skill's own directory. It is relative on purpose - the inventory stays machine-independent,
    # and `../references` reads as the same hop the citing SKILL.md makes with `../../references/`.
    dest = f[4] if len(f) > 4 else ''
    root, note, spec = resolve(pid)
    # dest is hand-written and ends up as the argument to `mv` and, on rollback, `rm -rf`. One
    # level up is the whole point (`../references`); two is a typo with a home directory at the
    # other end of it. Probe it against a two-segment fake root: `a/b` stands for
    # <parent>/<skills>, so a legal dest normalises to something strictly inside `a`.
    if dest:
        probe = os.path.normpath(os.path.join('a', 'b', dest))
        if not probe.startswith('a' + os.sep) or probe == 'a':
            note = 'bad-dest|%s escapes the skills root parent - refusing to touch it' % dest
    if spec and spec not in specs:
        specs.append(spec)
    up = os.path.join(root, sub) if root else ''
    if up and not os.path.isdir(up):
        up, note = '', 'upstream-missing|%s not present under %s' % (sub, root)
    # Forward slashes only: a mixed C:/a\b path is what os.path.join produces on Windows, and
    # cygpath silently mistranslates it.
    rows.append([skill, pid, sub, base, up.replace('\\', '/'), tree_hash(up), note, dest])

if mode == 'mirrors':
    for pid, url, ref, rel, kind in specs:
        print('\t'.join([pid, url, ref, rel, kind]))
else:
    # \x1f, not \t: tab is IFS *whitespace*, so bash's `read` collapses a run of tabs into
    # one delimiter and an empty field mid-record shifts every field after it left by one.
    # Exactly one of up/note is empty on every row, so a tab-separated record misparses on
    # every unresolvable row - which is why refresh-needed and upstream-missing never classified.
    for r in rows:
        print('\x1f'.join(r))
PY
}

# Emits, US-separated (see $US): skill, plugin, subpath, baseline, upstream-dir, upstream-hash,
# note, live-dir.
# upstream-dir is empty exactly when note is set. Paths come back native and are converted here,
# because MSYS mangles argv into Windows form on the way in but leaves stdout alone.
#
# live-dir is resolved here, once, so no caller ever composes $SKILLS_DIR/$skill itself: the
# inventory's optional dest column is what lets a row vendor something that is not a skill and does
# not live under $SKILLS_DIR - the shared references/ tree the agent-skills bodies cite.
inventory_resolved() {
  local skill pid sub base up hash note dest
  py_helper resolve "$INVENTORY" "$PLUGINS_JSON" "$MARKETPLACES" "$MIRRORS" \
  | while IFS=$US read -r skill pid sub base up hash note dest; do
      [ -n "$up" ] && up=$(cygpath -u "$up" 2>/dev/null || echo "$up")
      printf "%s$US%s$US%s$US%s$US%s$US%s$US%s$US%s\n" \
             "$skill" "$pid" "$sub" "$base" "$up" "$hash" "$note" "$SKILLS_DIR/${dest:-$skill}"
    done
}

# Exact first-field match, never a regex: a name like `.*` must not silently match the first
# row (the old `grep -P "^$1\x1f"` did). The ($1 "") cast keeps the comparison a string one -
# awk would otherwise equate 01 and 1 numerically. $1 is a resolved-rows blob, $2 the skill name.
row_from() {                        # $1 resolved rows  $2 skill -> its row on stdout
  awk -F"$US" -v s="$2" '($1 "") == s{print; exit}' <<<"$1"
}

lookup() {                          # $1 skill -> resolved row, or exit 1
  local row
  row=$(row_from "$(inventory_resolved)" "$1")
  [ -n "$row" ] || return 1
  printf '%s\n' "$row"
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
  if command -v claude >/dev/null 2>&1; then
    if claude plugin marketplace update >/dev/null 2>&1; then
      echo "refresh: marketplace clones updated"
    else
      echo "refresh: WARNING 'claude plugin marketplace update' failed - clones may be stale" >&2
    fi
  else
    echo "refresh: WARNING claude CLI not on PATH - marketplace clones not updated" >&2
  fi

  sync_mirrors
  prune_mirrors
  # Partial failure stays exit 0: --check's REFRESH bucket is the real net, and one dead mirror
  # must not stop the rest of the fleet from being comparable. Total failure is the one state
  # nothing downstream can work around, so it alone exits nonzero.
  if [ "$MIRROR_FAILED" -gt 0 ]; then
    echo "refresh: done - $MIRROR_FAILED of $MIRROR_TOTAL mirrors failed"
    [ "$MIRROR_FAILED" -lt "$MIRROR_TOTAL" ] || return 1
  else
    echo "refresh: done - run --check"
  fi
}

# The fetching half of refresh, split out so --self-test can drive it without shelling out to the
# real `claude plugin marketplace update`. Two spec kinds flow through the same stream:
#   sha - catalog-pinned and immutable: skip a present mirror, fetch the pinned commit otherwise.
#         A url-pinned plugin is the one kind whose current content is otherwise nowhere on disk:
#         the catalog records a sha, and the install cache is frozen behind it. Fetching the pinned
#         commit shallow is a couple of seconds and needs no plugin re-install, which would touch
#         enabledPlugins.
#   git - branch-tracking and mutable: a present mirror is stale by definition, so fetch and
#         hard-reset to the branch tip every run - skipping it would recreate the frozen-cache
#         failure this whole skill exists to prevent. A failed fetch keeps the last-known-good
#         mirror with a loud WARNING: stale-but-present beats reporting nothing, and the WARNING is
#         the signal that --check compared against the old tip.
sync_mirrors() {
  local pid url ref rel kind mirror
  MIRROR_TOTAL=0; MIRROR_FAILED=0    # globals on purpose: refresh() reports them after we return
  while IFS=$'\t' read -r pid url ref rel kind; do
    [ -n "$pid" ] || continue
    MIRROR_TOTAL=$((MIRROR_TOTAL + 1))
    mirror="$MIRRORS/$rel"
    if [ "$kind" = git ]; then
      if [ -d "$mirror/.git" ]; then
        echo "refresh: updating $pid at $ref"
        if ! { git -C "$mirror" fetch -q --depth 1 origin "$ref" \
               && git -C "$mirror" reset -q --hard FETCH_HEAD; }; then
          echo "refresh: WARNING fetch failed for $pid - keeping the mirror at the last known tip" >&2
          MIRROR_FAILED=$((MIRROR_FAILED + 1))
        fi
        continue
      fi
    elif [ -d "$mirror/.git" ]; then
      echo "refresh: $pid already mirrored at ${ref:0:12}"; continue
    fi
    echo "refresh: mirroring $pid at ${ref:0:12}"
    rm -rf "$mirror"; mkdir -p "$mirror"
    if git init -q "$mirror" \
       && git -C "$mirror" remote add origin "$url" \
       && git -C "$mirror" fetch -q --depth 1 origin "$ref" \
       && git -C "$mirror" checkout -q FETCH_HEAD; then
      :
    else
      rm -rf "$mirror"
      rmdir "$(dirname "$mirror")" 2>/dev/null || true    # the mkdir -p parent: empty now, and prune never sweeps depth 1
      echo "refresh: FAILED to mirror $pid at ${ref:0:12} from $url" >&2
      MIRROR_FAILED=$((MIRROR_FAILED + 1))
    fi
  done < <(py_helper mirrors "$INVENTORY" "$PLUGINS_JSON" "$MARKETPLACES" "$MIRRORS")
}

# A mirror is resolved upstream, not a leftover, so the one at the currently pinned sha survives:
# --check and --diff need a tree to compare against on every later run, and re-fetching it on each
# invocation would put a network call in the middle of an inspection command. Every other mirror is
# dead the moment the pin moves, and goes.
prune_mirrors() {                   # $1 --dry-run to report only
  local dry=${1:-} keep d rel n=0
  [ -d "$MIRRORS" ] || return 0
  # $4 is the rel the python side computed - exactly the two on-disk segments for both spec kinds,
  # so the 12-char-sha truncation knowledge lives only there.
  keep=$(py_helper mirrors "$INVENTORY" "$PLUGINS_JSON" "$MARKETPLACES" "$MIRRORS" \
         | awk -F'\t' 'NF>=4 {print $4}')
  while IFS= read -r d; do
    rel=${d#"$MIRRORS"/}
    if ! grep -qxF "$rel" <<<"$keep"; then
      n=$((n + 1)); [ -n "$dry" ] || rm -rf "$d"
    fi
  done < <(find "$MIRRORS" -mindepth 2 -maxdepth 2 -type d 2>/dev/null)
  [ "$n" -eq 0 ] || echo "clean: $n stale mirror(s)$([ -n "$dry" ] && echo ' (dry run)' || echo ' removed')"
  local live; live=$(grep -c . <<<"$keep" || true)
  [ "$live" -eq 0 ] || echo "clean: $live mirror(s) kept at the pinned sha or tracked branch (resolved upstream, not a leftover)"
}

# --- protected local edits as data ---------------------------------------------------------------
# The protected edits (L-flag index in SKILL.md, full entries in RULINGS.md) are line
# replacements against a known upstream text, so they are data, not prose:
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
  # back a re-vendor that was perfectly applicable. Strip it here so the patch owns only the
  # protected edits.
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
  local skill pid sub base up hash note live state d n r pf
  local appliable='' review='' blocked='' stale='' regimes=0 reg_local=0 reg_up=0 reg_unres=0 unmapped_slash=0
  # Mirrors lint's one refusal: on a missing skills root every row would fall through to
  # not-vendored/BLOCKED, which reads as a fleet-wide loss rather than an unset $SKILLS_DIR.
  [ -d "$SKILLS_DIR" ] || { echo "check: no skills directory at $SKILLS_DIR" >&2; return 1; }
  # Flat-layout leftovers from before the scripts/ split - a resync.sh/inventory.tsv at the skill
  # root, a scripts/scripts/ nesting - drift silently beside the copies INVENTORY/PATCHES resolve
  # to, and SCRIPT_DIR (their anchor) is that same dir. Warned, never bucketed: a bucket entry is
  # an inventory row, and the REGIME footer reconciles rows - an artifact with no row has no state.
  local a
  for a in "$SCRIPT_DIR/../resync.sh" "$SCRIPT_DIR/../inventory.tsv" "$SCRIPT_DIR/scripts"; do
    [ -e "$a" ] \
      && echo "check: WARNING legacy flat-layout leftover $a - delete it, the scripts/ copies are authoritative" >&2
  done
  printf '%-32s %-6s %s\n' SKILL REGIME 'STATE / DETAIL'
  while IFS=$US read -r skill pid sub base up hash note live; do
    pf=$(patch_file "$skill")
    # The diff ignores the regime line, so report it separately: without this a skill that lost
    # its L6 flag out of band would read as identical, which is the one failure this whole skill
    # exists to catch. Reported, not asserted - a deliberate promotion needs no bookkeeping.
    if has_regime "$live/SKILL.md" 2>/dev/null; then
      r='slash'; regimes=$((regimes + 1))
      # local: the flag exists only in the live copy, so restore_regime (the L6 ledger) owns it.
      # upstream: upstream ships it - neither re-add nor strip. A row with no resolvable upstream
      # ($up empty, note set) still counts in the total but cannot classify; the footer reports
      # those apart so its arithmetic reconciles on an unhealthy fleet too.
      if [ -z "$up" ]; then
        reg_unres=$((reg_unres + 1))
      elif has_regime "$up/SKILL.md" 2>/dev/null; then
        reg_up=$((reg_up + 1))
      else
        reg_local=$((reg_local + 1))
      fi
    else
      r='-'
    fi
    # The note outranks a missing directory: a new row whose upstream is unresolvable is
    # REFRESH or BLOCKED, not APPLIABLE, and reporting it appliable puts a row the user cannot
    # apply into the one list they authorise from.
    if [ -n "$note" ]; then
      state=${note%%|*}; d=${note#*|}
    elif [ ! -d "$live" ]; then
      # A `-` baseline is how a row is authored before its first vendor, so a missing directory
      # there is the intended state and --apply installs it. A missing directory under a *real*
      # baseline is a copy that disappeared, which is not something to overwrite unasked.
      if [ "$base" = '-' ]; then
        state=unvendored;   d="new row - --apply will vendor it into $live"
      else
        state=not-vendored; d="no $live"
      fi
    else
      n=$(drift_diff "$up" "$live" | grep -c . || true)
      if [ "$base" = "$hash" ]; then
        if [ "$n" -eq 0 ]; then
          state=identical; d=''
        elif [ ! -f "$pf" ]; then
          # Upstream is at the baseline, so this diff is unambiguously a local edit - and this is
          # the only window in which it is. Capture it now or the next upstream move eats it.
          state=unsnapshotted; d="$n diff lines, no patch - run --snapshot $skill"
        elif [ -n "$(diff -q <(gen_patch "$up" "$live") "$pf" 2>&1)" ]; then
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
      upstream-changed|unvendored) appliable+=" $skill" ;;
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
  # Only a directory with a SKILL.md is a skill: synced/ is the `skills` CLI's sync area,
  # not a skill, and counting it inflated the unmapped count against the no-upstream originals.
  unmapped=$(comm -23 \
    <(cd "$SKILLS_DIR" && for d in */; do [ -f "${d}SKILL.md" ] && printf '%s\n' "${d%/}"; done | sort) \
    <(cut -f1 "$INVENTORY" | grep -v '^#' | grep . | sort))
  for d in $unmapped; do
    has_regime "$SKILLS_DIR/$d/SKILL.md" 2>/dev/null && unmapped_slash=$((unmapped_slash + 1))
  done
  echo "UNMAPPED: $(echo $unmapped)   # expected: the originals with no upstream"
  # Denominator counts rows with no dest override only: a dest row vendors a shared asset tree, has
  # no SKILL.md and no invocation regime, so counting it would inflate the figure the footer
  # reconciles. The local/upstream split and the unmapped count are computed here; the ledger in
  # RULINGS.md is the why behind each flag, not the arithmetic.
  local unresolved=''
  [ "$reg_unres" -eq 0 ] || unresolved=" (+ $reg_unres unresolvable)"
  echo "REGIME: $regimes/$(awk -F'\t' '!/^#/ && NF>=4 && $5=="" {n++} END{print n+0}' "$INVENTORY")" \
       "mapped slash-only ($reg_local local, $reg_up upstream)$unresolved + $unmapped_slash/$(echo $unmapped | wc -w) unmapped slash-only - reconcile against the regime ledger (RULINGS.md)"
}

# --- lint --------------------------------------------------------------------------------------
# Report-only sweep of the references between the vendored skills - the mechanical half of
# the L2/L3/L5/L7/L8 lesson. A re-vendor can reintroduce a pointer that does not resolve at
# user scope, and no other check in this script sees it. Findings are candidates, not
# verdicts: prose-vs-instruction is ruled in SKILL.md / RULINGS.md, so this exits 0 whatever it finds -
# reported, not asserted, like the REGIME column. A missing skills root is the one refusal.
#
#   PATH   a path with intra-tree intent - ./ or ../ anchored, under an intra-skill directory
#          (references/, scripts/, assets/, agents/), or naming a sibling skill directory -
#          that does not resolve from where it is written to resolve from
#   UPATH  a path written against the upstream checkout layout (skills/...) - it resolves
#          only from a checkout CWD; separate category because upstream bodies carry them
#          legitimately (CREATION-LOG notes, example transcripts)
#   INSTR  an instruction naming a skill that is not vendored, or that is slash-only - no
#          skill can reach it, the failure L2 and L7 record
#   COND   the same shape guarded by an "if available" - a soft dependency, listed apart
#   A path with no intra-tree intent (CONTEXT.md, tasks/plan.md, docs/..., a spec template)
#   names an artifact of the project the skill runs against, not a fleet file: not this
#   sweep's business, skipped without comment.
lint() {
  # The one hard error: reporting on a skills root that does not exist would read as "fleet
  # is clean", which is worse than a crash - refuse it cleanly instead of tracebacking.
  [ -d "$SKILLS_DIR" ] || { echo "lint: no skills directory at $SKILLS_DIR" >&2; return 1; }
  "$PY" - "$SKILLS_DIR" <<'PY'
import os, re, sys

root = sys.argv[1]
MD_LINK = re.compile(r'\]\(([^)\s]+)\)')
CODE_PATH = re.compile(r'`([^`\n]+?\.md)`')
DISPATCH = [
    re.compile(r'call the skill tool with ["\'`]([A-Za-z][\w-]*)["\'`]', re.I),
    re.compile(r'\binvoke [`"]([A-Za-z][\w-]*)[`"]', re.I),
    re.compile(r'\bwith (?:the )?`([A-Za-z][\w-]*)` skill\b', re.I),
    re.compile(r'\b(?:use|run|execute) (?:the )?`([A-Za-z][\w-]*)` skill\b', re.I),
]
INTRA_DIRS = ('references', 'scripts', 'assets', 'agents')
PLACEHOLDER = re.compile(r'[<>{}\[\]*?]')

def path_class(dirpath, t):
    """None = resolves, or no intra-tree intent to verify. PATH/UPATH = a finding."""
    if not t or '://' in t or t.startswith(('http', 'mailto:', '/', '~')):
        return None
    if PLACEHOLDER.search(t) or ' ' in t:
        return None
    if t.startswith('skills/'):
        return None if os.path.exists(os.path.normpath(os.path.join(root, t))) else 'UPATH'
    seg1 = t.split('/', 1)[0]
    if t.startswith(('./', '../')) or seg1 in INTRA_DIRS:
        base = dirpath
    elif '/' in t and os.path.isdir(os.path.join(root, seg1)):
        base = root    # sibling-skill path, skills-root-relative (the build-mcp-* unit's form)
    else:
        return None
    return 'PATH' if not os.path.exists(os.path.normpath(os.path.join(base, t))) else None

def is_skill(name):
    return os.path.isfile(os.path.join(root, name, 'SKILL.md'))

def slash_only(name):
    # One predicate with has_regime (resync.sh) and REGIME_RE: prefix `disable-model-invocation:
    # *true`, frontmatter only - a body line documenting the flag is not the flag. Change the
    # three encodings together.
    try:
        with open(os.path.join(root, name, 'SKILL.md'), encoding='utf-8', errors='replace') as fh:
            if fh.readline().rstrip('\r\n') != '---':
                return False
            for ln in fh:
                if ln.rstrip('\r\n') == '---':
                    return False
                if re.match(r'disable-model-invocation: *true', ln):
                    return True
    except OSError:
        pass
    return False

findings = []
names = sorted(d for d in os.listdir(root) if is_skill(d))
for name in names:
    if name == 'skills-resync':
        continue    # its body quotes the instruction forms this sweep matches - taxonomy, not fleet
    base = os.path.join(root, name)
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for fn in sorted(filenames):
            if not fn.endswith('.md'):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, base).replace(os.sep, '/')
            try:
                with open(path, encoding='utf-8', errors='replace') as fh:
                    lines = fh.read().splitlines()
            except OSError:
                continue
            for i, line in enumerate(lines, 1):
                where = '%s:%d' % (rel, i)
                targets = [m.group(1).split('#')[0] for m in MD_LINK.finditer(line)]
                targets += [m.group(1) for m in CODE_PATH.finditer(line)]
                for t in targets:
                    cls = path_class(dirpath, t)
                    if cls:
                        findings.append((name, where, cls, t))
                hits = []
                for rx in DISPATCH:
                    hits += rx.findall(line)
                for t in sorted(set(hits)):
                    if t == name or not re.fullmatch(r'[a-z][a-z0-9-]*', t):
                        continue
                    if 'available' in line.lower():
                        # a guarded dispatch is still dead when the target is missing or
                        # unreachable - carry the verdict, not just the guard
                        why = ('non-vendored' if not is_skill(t)
                               else 'unreachable (slash-only)' if slash_only(t) else 'reachable')
                        findings.append((name, where, 'COND', 'guarded, %s: %s' % (why, t)))
                    elif not is_skill(t):
                        findings.append((name, where, 'INSTR', 'non-vendored: ' + t))
                    elif slash_only(t):
                        findings.append((name, where, 'INSTR', 'unreachable (slash-only): ' + t))

for name, where, cls, detail in findings:
    print('%-30s %-32s %-6s %s' % (name, where, cls, detail))
print("LINT: %d finding(s) in %d skill(s) - candidates only, prose-vs-instruction is ruled in SKILL.md / RULINGS.md"
      % (len(findings), len(set(f[0] for f in findings))))
PY
}

# --- apply -------------------------------------------------------------------------------------
# Stage, verify, back up, swap. Nothing under $SKILLS_DIR is touched until a verified copy exists,
# so a failed copy can never leave a skill half-written. Replacement is wholesale, not a merge: a
# stale file left behind by an upstream deletion is drift no later diff would catch.
apply_one() {                       # $1 skill  $2 upstream  $3 work  $4 live dir
  local skill=$1 up=$2 work=$3 live=$4
  local stage="$work/stage/$skill" backup="$work/backup/$skill" regime=no patched='' fresh=''

  [ -d "$up" ] || { echo "  $skill: upstream missing ($up)" >&2; return 1; }
  # An absent live directory is the initial vendor of a new inventory row, not an error: there is
  # simply nothing to back up, so a later failure removes the new copy instead of restoring one.
  # check() has already refused this for a row carrying a real baseline, where absence means loss.
  [ -d "$live" ] || fresh=yes

  # `grep && regime=yes` would return non-zero for a skill with no regime line, which under set -e
  # aborts apply_one before it stages anything whenever it is called outside a condition.
  if has_regime "$live/SKILL.md" 2>/dev/null; then regime=yes; fi

  rm -rf "$work/stage" "$work/backup"; mkdir -p "$work/stage" "$work/backup"
  cp -r "$up" "$stage"
  # A copy must be byte-identical - no --strip-trailing-cr here, or a mangled copy verifies clean.
  if ! diff -rq "$up" "$stage" >/dev/null; then
    echo "  $skill: staged copy does not match upstream, nothing changed" >&2; return 1
  fi

  [ -n "$fresh" ] || mv "$live" "$backup"
  mkdir -p "$(dirname "$live")"
  if ! mv "$stage" "$live"; then
    [ -n "$fresh" ] || mv "$backup" "$live"
    echo "  $skill: swap failed, nothing changed" >&2; return 1
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
      rm -rf "$live"; [ -n "$fresh" ] || mv "$backup" "$live"
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
  if ! verify_patch "$skill" "$up" "$live"; then
    rm -rf "$live"; [ -n "$fresh" ] || mv "$backup" "$live"
    echo "  $skill: post-apply tree does not match upstream+patch, ROLLED BACK" >&2; return 1
  fi
  echo "  $skill: ${fresh:+vendored (new) }written$([ "$regime" = yes ] && echo ' +regime')$patched +verified" >&2
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
    if len(f) >= 4 and f[0] in pairs:
        f[3] = pairs[f[0]]
        line = '\t'.join(f) + '\n'
    out.append(line)
open(inv, 'w', encoding='utf-8', newline='\n').writelines(out)
PY
}

apply() {
  local work written=0 failed=0 rebase=() skill row base up hash note live resolved
  work=$(mktemp -d "${TMPDIR:-/tmp}/skills-resync-work-XXXXXX")
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT        # fires on success, failure and interrupt alike

  # Resolve once, not per skill: py_helper resolve walks and tree-hashes every upstream tree, so
  # `--apply a b c` must not pay for that three times. Rows are consumed only inside the loop
  # below - rebase_baselines rewrites the inventory afterwards and nothing reads $resolved again.
  resolved=$(inventory_resolved)

  for skill in "$@"; do
    row=$(row_from "$resolved" "$skill")
    if [ -z "$row" ]; then
      echo "  $skill: not in inventory.tsv" >&2; failed=$((failed + 1)); continue
    fi
    base=$(cut -d"$US" -f4 <<<"$row"); up=$(cut -d"$US" -f5 <<<"$row")
    hash=$(cut -d"$US" -f6 <<<"$row"); note=$(cut -d"$US" -f7 <<<"$row"); live=$(cut -d"$US" -f8 <<<"$row")
    if [ -n "$note" ]; then
      echo "  $skill: ${note%%|*} - ${note#*|}" >&2; failed=$((failed + 1)); continue
    fi
    # Interlock: an unsnapshotted local edit is the one thing the swap destroys with no way to
    # replay it - and it is only *detectable* while upstream still sits at the baseline. Refuse
    # exactly that case. Comparing against a moved upstream instead would read the upstream change
    # itself as an uncaptured edit and refuse every unedited skill, which is the mainline update.
    # `unvendored` is a `-` baseline and nothing else. Under a real baseline a missing directory
    # is a copy that was lost, and apply_one would now happily re-create it over whatever removed
    # it - so the rule check() reports is enforced here too, where the write actually happens.
    if [ ! -d "$live" ] && [ "$base" != '-' ]; then
      echo "  $skill: refused - $live is missing under baseline $base, so this is not a new row" >&2
      failed=$((failed + 1)); continue
    fi
    if [ "$base" = "$hash" ] && [ ! -f "$(patch_file "$skill")" ] \
       && [ -n "$(drift_diff "$up" "$live")" ]; then
      echo "  $skill: refused - uncaptured local edits (run --snapshot $skill first)" >&2
      failed=$((failed + 1)); continue
    fi
    if apply_one "$skill" "$up" "$work" "$live"; then
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
  local skill row up base hash note live n resolved; local rc=0
  mkdir -p "$PATCHES"
  resolved=$(inventory_resolved)
  for skill in "$@"; do
    row=$(row_from "$resolved" "$skill")
    if [ -z "$row" ]; then
      echo "  $skill: not in inventory.tsv" >&2; rc=1; continue
    fi
    base=$(cut -d"$US" -f4 <<<"$row"); up=$(cut -d"$US" -f5 <<<"$row")
    hash=$(cut -d"$US" -f6 <<<"$row"); note=$(cut -d"$US" -f7 <<<"$row"); live=$(cut -d"$US" -f8 <<<"$row")
    if [ -n "$note" ]; then
      echo "  $skill: ${note%%|*} - ${note#*|}" >&2; rc=1; continue
    fi
    if [ "$base" != "$hash" ]; then
      echo "  $skill: refused - upstream moved to $hash; reconcile by hand first" >&2
      rc=1; continue
    fi
    if [ -z "$(drift_diff "$up" "$live")" ]; then
      rm -f "$(patch_file "$skill")"
      echo "  $skill: no local edits, patch removed"; continue
    fi
    gen_patch "$up" "$live" > "$(patch_file "$skill")"
    # Prove it replays before trusting it: a patch that does not reproduce the live tree is worse
    # than none, because --check would then read the skill as protected when it is not.
    if verify_patch "$skill" "$up" "$live"; then
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
verify_patch() {                    # $1 skill  $2 upstream  $3 live dir
  local t ok=0; t=$(mktemp -d "${TMPDIR:-/tmp}/skills-resync-vfy-XXXXXX")
  cp -r "$2" "$t/x"
  replay_patch "$1" "$t/x" >/dev/null 2>&1 \
    && [ -z "$(diff -r --strip-trailing-cr -I "$REGIME_RE" "$t/x" "$3")" ] || ok=1
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
  local dry='' p targets=() young=0
  case "${1:-}" in
    '')        ;;
    --dry-run) dry=1 ;;
    *)         echo "clean: unexpected argument '$1' (only --dry-run)" >&2; return 2 ;;
  esac
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

  apply_one demo "$root/up/demo" "$root/work" "$root/skills/demo" 2>/dev/null
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
  if apply_one demo "$root/up/absent" "$root/work" "$root/skills/demo" 2>/dev/null; then
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
  verify_patch demo "$root/up2/demo" "$root/skills2/demo" \
    || { echo "self-test FAIL: fresh snapshot does not replay" >&2; return 1; }

  demo_body keep-me tail-v2 > "$root/up2/demo/SKILL.md"
  apply_one demo "$root/up2/demo" "$root/work2" "$root/skills2/demo" 2>/dev/null \
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
  if apply_one demo "$root/up3/demo" "$root/work3" "$root/skills3/demo" 2>/dev/null; then
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

  # --- lookup is an exact first-field match, never a regex ---------------------------------------
  # The old `grep -P "^$1\x1f"` turned a regex-shaped name into a pattern: --diff '.*' silently
  # operated on whatever row the pattern hit first. row_from compares the field as a string.
  printf 'other\tp@m\tskills/demo\t0\n' >> "$INVENTORY"
  [ "$(lookup demo | wc -l)" = 1 ] \
    || { echo "self-test FAIL: lookup returned more than one row" >&2; return 1; }
  if lookup '.*' >/dev/null; then
    echo "self-test FAIL: a regex-shaped name matched a row" >&2; return 1
  fi
  if lookup dem >/dev/null; then
    echo "self-test FAIL: a name prefix matched a row" >&2; return 1
  fi
  printf '01\tp@m\tskills/demo\t0\n' >> "$INVENTORY"
  if lookup 1 >/dev/null; then
    echo "self-test FAIL: a numeric-looking name matched a different row (awk strnum comparison)" >&2; return 1
  fi
  lookup 01 >/dev/null \
    || { echo "self-test FAIL: exact numeric row not found" >&2; return 1; }
  sed -i -e '/^other\t/d' -e '/^01\t/d' "$INVENTORY"

  # --- one resolution pass serves a multi-skill apply ---------------------------------------------
  # apply() resolves the inventory once and slices rows out of the capture, so two skills applied
  # in one invocation must both land - proving the single capture carries every row.
  mkdir -p "$root/up4/p/skills/demo2" "$root/up4/p/skills/demo3" \
           "$root/skills4/demo2" "$root/skills4/demo3"
  printf -- '---\nname: demo2\n---\nUP2\n' > "$root/up4/p/skills/demo2/SKILL.md"
  printf -- '---\nname: demo2\n---\nup2-old\n' > "$root/skills4/demo2/SKILL.md"
  printf -- '---\nname: demo3\n---\nUP3\n' > "$root/up4/p/skills/demo3/SKILL.md"
  printf -- '---\nname: demo3\n---\nup3-old\n' > "$root/skills4/demo3/SKILL.md"
  printf 'demo2\tp@m\tskills/demo2\t0000000000000000\ndemo3\tp@m\tskills/demo3\t0000000000000000\n' >> "$INVENTORY"
  apply demo2 demo3 >/dev/null 2>&1 \
    || { echo "self-test FAIL: multi-skill apply failed" >&2; return 1; }
  grep -q '^UP2$' "$root/skills4/demo2/SKILL.md" && grep -q '^UP3$' "$root/skills4/demo3/SKILL.md" \
    || { echo "self-test FAIL: multi-skill apply missed a skill" >&2; return 1; }
  sed -i '/^demo[23]\t/d' "$INVENTORY"
  rm -rf "$root/skills4/demo2" "$root/skills4/demo3"

  # An uncaptured local edit is still refused - upstream sits at the baseline, so it is detectable.
  printf -- '---\nname: demo\n---\nHAND-EDIT\n' > "$root/skills4/demo/SKILL.md"
  if apply demo >/dev/null 2>&1; then
    echo "self-test FAIL: apply overwrote an uncaptured local edit" >&2; return 1
  fi
  grep -q '^HAND-EDIT$' "$root/skills4/demo/SKILL.md" \
    || { echo "self-test FAIL: refused apply still touched the live copy" >&2; return 1; }

  # An unresolvable upstream must classify, and must outrank a missing directory. This is the
  # regression site for the record-separator bug: `up` is empty exactly when `note` is set, and
  # under tab-separated records bash's `read` collapsed the gap and shifted every later field, so
  # `note` arrived empty and the row fell through to a diff against a garbage path. Nothing else
  # in this file exercises a row with an empty field in the middle.
  printf 'ghost\tabsent@nomarket\tskills/ghost\t-\n' >> "$INVENTORY"
  case "$(check)" in *'upstream-missing'*) ;;
    *) echo "self-test FAIL: an unresolvable upstream does not classify" >&2; return 1 ;;
  esac
  case "$(check)" in *'APPLIABLE: ghost'*)
        echo "self-test FAIL: a new row with no upstream is offered as APPLIABLE" >&2; return 1 ;;
  esac
  sed -i '/^ghost/d' "$INVENTORY"

  # A directory with no SKILL.md is not a skill and must not count as unmapped: synced/ (the
  # `skills` CLI's sync area) made the printed line read +5 against L6's documented +4.
  mkdir -p "$root/skills4/not-a-skill"
  case "$(check)" in *not-a-skill*)
        echo "self-test FAIL: a directory with no SKILL.md counted as unmapped" >&2; return 1 ;;
  esac
  rmdir "$root/skills4/not-a-skill"

  # A vendored copy that disappeared under a real baseline is loss. check() reports it BLOCKED;
  # apply() must refuse it too, because --apply takes a name directly and would otherwise
  # re-create the directory over whatever removed it.
  rm -rf "$root/skills4/demo"
  if apply demo >/dev/null 2>&1; then
    echo "self-test FAIL: apply re-created a copy lost under a real baseline" >&2; return 1
  fi
  [ ! -e "$root/skills4/demo" ] \
    || { echo "self-test FAIL: refused apply wrote the directory anyway" >&2; return 1; }

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
  apply_one demo "$root/up5/demo" "$root/work5" "$root/skills5/demo" 2>/dev/null \
    || { echo "self-test FAIL: apply of a body-mention skill failed" >&2; return 1; }
  has_regime "$root/skills5/demo/SKILL.md" \
    || { echo "self-test FAIL: regime flag lost on a skill that documents it in prose" >&2; return 1; }
  [ "$(awk '/^---\r?$/{f++} f==1&&/^disable-model-invocation/{c++} END{print c}' "$root/skills5/demo/SKILL.md")" = 1 ] \
    || { echo "self-test FAIL: regime flag duplicated after restore" >&2; return 1; }

  # --- a new row vendors on first --apply, and a dest column puts it outside $SKILLS_DIR ---------
  # The shared references/ tree the agent-skills bodies cite is not a skill: it has no SKILL.md and
  # sits beside $SKILLS_DIR, not inside it. Both halves are exercised together because they arrived
  # together - a dest row has no live directory until the first apply creates one, so without the
  # initial-vendor path the row could never leave BLOCKED.
  #
  # `-` as the baseline is what separates the two: never-vendored, so write it. A missing directory
  # under a *real* baseline is a copy that was lost, and must stay BLOCKED rather than be silently
  # re-created over whatever removed it.
  mkdir -p "$root/up6/p/refs" "$root/skills6" "$root/patches6"
  SKILLS_DIR="$root/skills6"; PATCHES="$root/patches6"; INVENTORY="$root/inv6.tsv"
  PLUGINS_JSON="$root/plugins6.json"
  printf 'shared\n' > "$root/up6/p/refs/definition-of-done.md"
  "$PY" -c 'import json,sys; json.dump({"plugins":{"p@m":[{"installPath":sys.argv[1],
            "gitCommitSha":"deadbeefdeadbeef"}]}}, open(sys.argv[2],"w"))' \
       "$root/up6/p" "$PLUGINS_JSON"
  printf 'refs\tp@m\trefs\t-\t../references\n' > "$INVENTORY"
  case "$(check)" in *'APPLIABLE: refs'*) ;;
    *) echo "self-test FAIL: a new row with a - baseline is not APPLIABLE" >&2; return 1 ;;
  esac
  apply refs >/dev/null 2>&1 \
    || { echo "self-test FAIL: initial vendor of a new row failed" >&2; return 1; }
  [ -f "$root/references/definition-of-done.md" ] \
    || { echo "self-test FAIL: dest column not honoured, nothing written at ../references" >&2; return 1; }
  [ ! -e "$root/skills6/refs" ] \
    || { echo "self-test FAIL: dest row also written under \$SKILLS_DIR" >&2; return 1; }
  [ "$(cut -f4 "$INVENTORY")" = "$(py_helper hash "$root/up6/p/refs")" ] \
    || { echo "self-test FAIL: baseline not rebased on a 5-column row" >&2; return 1; }
  case "$(check)" in *'identical'*) ;;
    *) echo "self-test FAIL: re-check after the initial vendor does not read identical" >&2; return 1 ;;
  esac
  rm -rf "$root/references"
  case "$(check)" in *'BLOCKED: refs'*) ;;
    *) echo "self-test FAIL: a copy lost under a real baseline is not BLOCKED" >&2; return 1 ;;
  esac

  # --- a git+<repo>@<branch> row tracks a plain repo's branch tip --------------------------------
  # No marketplace involved: the inventory row is the whole spec, the mirror is mutable (a second
  # sync must fetch+reset to the new tip, not skip), the row vendors and re-vendors like any other,
  # and prune keeps the mirror while the row exists. The repo is a local path - resolve() uses such
  # a url verbatim, and MSYS git fetches local-path remotes shallow without complaint.
  local src=$root/gitsrc gm
  git init -q -b main "$src"
  mkdir -p "$src/skills/demo"
  printf -- '---\nname: demo\n---\ngit-v1\n' > "$src/skills/demo/SKILL.md"
  git -C "$src" add -A
  git -C "$src" -c user.email=t@t -c user.name=t commit -qm v1
  mkdir -p "$root/skills7" "$root/patches7"
  SKILLS_DIR="$root/skills7"; PATCHES="$root/patches7"
  INVENTORY="$root/inv7.tsv"; PLUGINS_JSON="$root/plugins7.json"; printf '{}' > "$PLUGINS_JSON"
  printf 'demo\tgit+%s@main\tskills/demo\t-\n' "$src" > "$INVENTORY"
  gm="$MIRRORS/git+${src//\//__}/main"
  sync_mirrors
  grep -q '^git-v1$' "$gm/skills/demo/SKILL.md" \
    || { echo "self-test FAIL: git mirror not cloned at the branch tip" >&2; return 1; }
  case "$(check)" in *'APPLIABLE: demo'*) ;;
    *) echo "self-test FAIL: git row is not APPLIABLE once mirrored" >&2; return 1 ;;
  esac
  apply demo >/dev/null 2>&1 \
    || { echo "self-test FAIL: initial vendor of a git row failed" >&2; return 1; }
  grep -q '^git-v1$' "$root/skills7/demo/SKILL.md" \
    || { echo "self-test FAIL: git row did not vendor upstream content" >&2; return 1; }
  # Second sync after a new commit: the mirror must move, proving fetch+reset ran and not the skip.
  printf -- '---\nname: demo\n---\ngit-v2\n' > "$src/skills/demo/SKILL.md"
  git -C "$src" add -A
  git -C "$src" -c user.email=t@t -c user.name=t commit -qm v2
  sync_mirrors
  grep -q '^git-v2$' "$gm/skills/demo/SKILL.md" \
    || { echo "self-test FAIL: tracking mirror did not move to the new branch tip" >&2; return 1; }
  apply demo >/dev/null 2>&1 \
    || { echo "self-test FAIL: re-vendor of a moved git row failed" >&2; return 1; }
  grep -q '^git-v2$' "$root/skills7/demo/SKILL.md" \
    || { echo "self-test FAIL: git row did not take the upstream update" >&2; return 1; }
  # Prune keeps the tracking mirror while its row exists; anything else at depth 2 goes.
  mkdir -p "$MIRRORS/gone/x"
  prune_mirrors >/dev/null
  [ -d "$gm" ] \
    || { echo "self-test FAIL: tracking mirror pruned while its row exists" >&2; return 1; }
  [ ! -d "$MIRRORS/gone/x" ] \
    || { echo "self-test FAIL: mirror with no row survived the prune" >&2; return 1; }
  # A malformed git pid classifies and never reaches APPLIABLE.
  printf 'bad\tgit+no-at-sign\tskills/x\t-\n' >> "$INVENTORY"
  case "$(check)" in *'upstream-missing'*) ;;
    *) echo "self-test FAIL: malformed git pid does not classify" >&2; return 1 ;;
  esac
  case "$(check)" in *'APPLIABLE: bad'*)
        echo "self-test FAIL: malformed git pid offered as APPLIABLE" >&2; return 1 ;;
  esac
  sed -i '/^bad\t/d' "$INVENTORY"
  grep -q '^bad' "$INVENTORY" \
    && { echo "self-test FAIL: malformed git pid row not removed from the fixture" >&2; return 1; }
  # scp-like git@host:path is malformed too: classify upstream-missing, emit no mirror spec -
  # https-prefixed it would sit REFRESH forever while sync_mirrors retried a garbage fetch.
  printf 'scp\tgit+git@github.com:o/r@main\tskills/x\t-\n' >> "$INVENTORY"
  case "$(check)" in *'upstream-missing  malformed git pid git+git@github.com:o/r@main'*) ;;
    *) echo "self-test FAIL: scp-like git pid not reported malformed" >&2; return 1 ;;
  esac
  case "$(check)" in *'APPLIABLE: scp'*)
        echo "self-test FAIL: scp-like git pid offered as APPLIABLE" >&2; return 1 ;;
  esac
  [ -z "$(py_helper mirrors "$INVENTORY" "$PLUGINS_JSON" "$MARKETPLACES" "$MIRRORS" | grep 'git@github.com')" ] \
    || { echo "self-test FAIL: scp-like git pid yielded a mirror fetch spec" >&2; return 1; }
  sed -i '/^scp\t/d' "$INVENTORY"
  case "$(check)" in *identical*) ;;
    *) echo "self-test FAIL: git row does not read identical after apply" >&2; return 1 ;;
  esac

  # --- mirror failures are counted; refresh fails only when every mirror failed -------------------
  # refresh used to exit 0 whatever happened to the mirrors, with failures buried in stderr
  # WARNINGs. sync_mirrors counts totals now; refresh reports them and exits nonzero only on a
  # total failure - partial stays 0 because --check's REFRESH bucket is the real net. refresh runs
  # inside a subshell with a stub claude first on PATH: bash persists `PATH=... func` assignments
  # after the call, and a real marketplace update must never run from the self-test.
  mkdir -p "$root/fakebin"
  printf '#!/bin/sh\nexit 0\n' > "$root/fakebin/claude"; chmod +x "$root/fakebin/claude"
  printf 'dead\tgit+%s@main\tskills/x\t-\n' "$root/nonexistent" >> "$INVENTORY"
  sync_mirrors >/dev/null 2>&1
  [ "$MIRROR_FAILED" = 1 ] && [ "$MIRROR_TOTAL" = 2 ] \
    || { echo "self-test FAIL: mirror failure not counted (got $MIRROR_FAILED of $MIRROR_TOTAL)" >&2; return 1; }
  if ! ( PATH="$root/fakebin:$PATH"; refresh ) >/dev/null 2>&1; then
    echo "self-test FAIL: refresh failed on a partial mirror failure" >&2; return 1
  fi
  sed -i '/^dead\t/d' "$INVENTORY"
  printf 'd1\tgit+%s@main\tskills/x\t-\nd2\tgit+%s@main\tskills/x\t-\n' \
         "$root/nonexistent" "$root/nonexistent2" > "$root/invfail.tsv"
  keep_inv=$INVENTORY; INVENTORY="$root/invfail.tsv"
  sync_mirrors >/dev/null 2>&1
  [ "$MIRROR_FAILED" = 2 ] && [ "$MIRROR_TOTAL" = 2 ] \
    || { echo "self-test FAIL: all-failed mirror count wrong (got $MIRROR_FAILED of $MIRROR_TOTAL)" >&2; return 1; }
  if ( PATH="$root/fakebin:$PATH"; refresh ) >/dev/null 2>&1; then
    echo "self-test FAIL: refresh exited 0 with every mirror failed" >&2; return 1
  fi
  INVENTORY="$keep_inv"

  # --- a git+ repo on a drive path is a url verbatim, not https-prefixed --------------------------
  printf 'drive\tgit+D:/x@main\tskills/x\t-\nhost\tgit+github.com/o/r@main\tskills/x\t-\n' > "$root/invurl.tsv"
  keep_inv=$INVENTORY; INVENTORY="$root/invurl.tsv"
  [ "$(py_helper mirrors "$INVENTORY" "$PLUGINS_JSON" "$MARKETPLACES" "$MIRRORS" \
       | awk -F'\t' '$1=="git+D:/x@main" {print $2}')" = 'D:/x' ] \
    || { echo "self-test FAIL: drive-path git repo was https-prefixed" >&2; return 1; }
  [ "$(py_helper mirrors "$INVENTORY" "$PLUGINS_JSON" "$MARKETPLACES" "$MIRRORS" \
       | awk -F'\t' '$1=="git+github.com/o/r@main" {print $2}')" = 'https://github.com/o/r' ] \
    || { echo "self-test FAIL: hostname git repo lost its https:// prefix" >&2; return 1; }
  # The url was only half of the drive-path fix: the mirror rel must also survive munge() with
  # no separator left, ':' included - a colon in a Windows path component names a directory no
  # mkdir can create, so the row would stay refresh-needed forever.
  case "$(py_helper mirrors "$INVENTORY" "$PLUGINS_JSON" "$MARKETPLACES" "$MIRRORS" \
         | awk -F'\t' '$1=="git+D:/x@main" {print $4}')" in
    *:*) echo "self-test FAIL: mirror rel still contains a colon" >&2; return 1 ;;
  esac
  # End-to-end where a drive form exists: a real repo addressed through it must mirror and
  # resolve. cygpath -m gives the C:/ mixed form; POSIX has no drive paths to exercise.
  if command -v cygpath >/dev/null 2>&1; then
    git init -q -b main "$root/drivesrc"
    mkdir -p "$root/drivesrc/skills/x"
    printf -- '---\nname: x\n---\ndrive-v1\n' > "$root/drivesrc/skills/x/SKILL.md"
    git -C "$root/drivesrc" add -A
    git -C "$root/drivesrc" -c user.email=t@t -c user.name=t commit -qm v1
    printf 'drive3\tgit+%s@main\tskills/x\t-\n' "$(cygpath -m "$root")/drivesrc" >> "$INVENTORY"
    sync_mirrors >/dev/null 2>&1
    # cygpath takes its path as an argument here - this build does not read stdin without one.
    upraw=$(py_helper resolve "$INVENTORY" "$PLUGINS_JSON" "$MARKETPLACES" "$MIRRORS" \
            | awk -F"$US" '$1=="drive3" {print $5}')
    updrv=$(cygpath -u "$upraw" 2>/dev/null || echo "$upraw")
    grep -q '^drive-v1$' "$updrv/SKILL.md" 2>/dev/null \
      || { echo "self-test FAIL: drive-path repo did not mirror (up='$updrv')" >&2; return 1; }
    sed -i '/^drive3\t/d' "$INVENTORY"
  fi
  INVENTORY="$keep_inv"

  # --- the lint: paths that do not resolve, instructions that cannot run ------------------------
  # helper is model-invoked (a clean dispatch target); solo is slash-only (unreachable from a
  # body); ghost is named by an instruction but not vendored; broken carries a dead intra-skill
  # link and a dead backticked path; not-a-skill has no SKILL.md and must not be scanned at
  # all; tasks/note.md has no intra-tree intent and must not be reported however dead.
  mkdir -p "$root/skills8/helper" "$root/skills8/solo" "$root/skills8/solo2" \
           "$root/skills8/ghost-caller" "$root/skills8/broken" "$root/skills8/not-a-skill"
  SKILLS_DIR="$root/skills8"
  printf -- '---\nname: helper\n---\ncontent\n' > "$root/skills8/helper/SKILL.md"
  printf -- '---\nname: solo\ndisable-model-invocation: true\n---\ncontent\n' > "$root/skills8/solo/SKILL.md"
  # Two spaces after the colon: the form a `startswith('disable-model-invocation: true')`
  # predicate missed while has_regime accepted it - the two encodings must agree.
  printf -- '---\nname: solo2\ndisable-model-invocation:  true\n---\ncontent\n' > "$root/skills8/solo2/SKILL.md"
  printf -- '---\nname: ghost-caller\n---\nCall the Skill tool with "ghost", see [x](references/gone.md), plus [log](tasks/note.md) and `skills/upstream/layout.md`.\nIf available, run the review with the `helper` skill.\nInvoke `solo` before the pass, then close with the `solo2` Skill.\n' > "$root/skills8/ghost-caller/SKILL.md"
  printf -- '---\nname: broken\n---\nRun the wrap-up with the `solo` skill, then read `references/missing.md`.\n' > "$root/skills8/broken/SKILL.md"
  printf -- 'no skill here, just [dead](also-gone.md)\n' > "$root/skills8/not-a-skill/NOTE.md"
  out=$(lint)
  case "$out" in *'non-vendored: ghost'*) ;;
    *) echo "self-test FAIL: lint missed a dispatch to a non-vendored skill" >&2; return 1 ;;
  esac
  case "$out" in *'unreachable'*) ;;
    *) echo "self-test FAIL: lint missed a dispatch to a slash-only skill" >&2; return 1 ;;
  esac
  case "$out" in *'gone.md'*) ;;
    *) echo "self-test FAIL: lint missed a dead markdown link" >&2; return 1 ;;
  esac
  case "$out" in *'missing.md'*) ;;
    *) echo "self-test FAIL: lint missed a dead backticked path" >&2; return 1 ;;
  esac
  case "$out" in *'UPATH'*) ;;
    *) echo "self-test FAIL: lint missed an upstream-layout path" >&2; return 1 ;;
  esac
  case "$out" in *'guarded, reachable: helper'*) ;;
    *) echo "self-test FAIL: lint missed a guarded conditional dispatch" >&2; return 1 ;;
  esac
  case "$out" in *'unreachable (slash-only): solo'*) ;;
    *) echo "self-test FAIL: lint missed a case-variant dispatch" >&2; return 1 ;;
  esac
  case "$out" in *'unreachable (slash-only): solo2'*) ;;
    *) echo "self-test FAIL: slash_only diverged from has_regime on a multi-space flag" >&2; return 1 ;;
  esac
  case "$out" in *tasks/note.md*|*not-a-skill*|*'helper '*)
        echo "self-test FAIL: lint reported a project artifact, a non-skill directory, or a clean skill" >&2; return 1 ;;
  esac

  # --- the REGIME footer computes the local/upstream/unmapped split --------------------------------
  # The footer used to report one count and leave the arithmetic to a hand-maintained paragraph.
  # check() classifies each slash-only row now: local means the flag exists only in the live copy
  # (restore_regime owns it), upstream means upstream ships it; unmapped slash-only is counted
  # apart because those skills have no row to classify from.
  mkdir -p "$root/up9/p/skills/a" "$root/up9/p/skills/b" "$root/skills9/a" "$root/skills9/b" \
           "$root/skills9/c" "$root/skills9/orig" "$root/skills9/orig2" "$root/patches9"
  SKILLS_DIR="$root/skills9"; PATCHES="$root/patches9"; INVENTORY="$root/inv9.tsv"
  PLUGINS_JSON="$root/plugins9.json"
  printf -- '---\nname: a\n---\nbody\n' > "$root/up9/p/skills/a/SKILL.md"
  printf -- '---\nname: a\ndisable-model-invocation: true\n---\nbody\n' > "$root/skills9/a/SKILL.md"
  printf -- '---\nname: b\ndisable-model-invocation: true\n---\nbody\n' > "$root/up9/p/skills/b/SKILL.md"
  cp "$root/up9/p/skills/b/SKILL.md" "$root/skills9/b/SKILL.md"
  # c is slash-only with an unresolvable upstream: it counts in the total, cannot classify, and
  # the footer must say so with its own clause instead of silently losing the row.
  printf -- '---\nname: c\ndisable-model-invocation: true\n---\nbody\n' > "$root/skills9/c/SKILL.md"
  printf -- '---\nname: orig\ndisable-model-invocation: true\n---\nbody\n' > "$root/skills9/orig/SKILL.md"
  printf -- '---\nname: orig2\n---\nbody\n' > "$root/skills9/orig2/SKILL.md"
  "$PY" -c 'import json,sys; json.dump({"plugins":{"p@m":[{"installPath":sys.argv[1],
            "gitCommitSha":"deadbeefdeadbeef"}]}}, open(sys.argv[2],"w"))' "$root/up9/p" "$PLUGINS_JSON"
  { printf 'a\tp@m\tskills/a\t%s\n' "$(py_helper hash "$root/up9/p/skills/a")"
    printf 'b\tp@m\tskills/b\t%s\n' "$(py_helper hash "$root/up9/p/skills/b")"
    printf 'c\tabsent@nomarket\tskills/c\t-\n'; } > "$INVENTORY"
  case "$(check)" in *'REGIME: 3/3 mapped slash-only (1 local, 1 upstream) (+ 1 unresolvable) + 1/2 unmapped'*) ;;
    *) echo "self-test FAIL: computed REGIME footer wrong" >&2; return 1 ;;
  esac

  # --- --clean takes --dry-run or nothing, and nothing else ----------------------------------------
  # The old `clean "${2:-}"` read any second argument as the dry-run flag. The recursive calls
  # pass the scratch world explicitly because the self-test's overrides are not exported.
  if clean bogus >/dev/null 2>&1; then
    echo "self-test FAIL: clean accepted a non --dry-run argument" >&2; return 1
  fi
  crc=0
  SKILLS_DIR="$SKILLS_DIR" PLUGIN_CACHE="$PLUGIN_CACHE" MIRRORS="$MIRRORS" MARKETPLACES="$MARKETPLACES" \
  INVENTORY="$INVENTORY" PATCHES="$PATCHES" PLUGINS_JSON="$PLUGINS_JSON" \
    bash "${BASH_SOURCE[0]}" --clean garbage >/dev/null 2>&1 || crc=$?
  [ "$crc" = 2 ] || { echo "self-test FAIL: --clean <garbage> did not usage-exit 2" >&2; return 1; }
  crc=0
  SKILLS_DIR="$SKILLS_DIR" PLUGIN_CACHE="$PLUGIN_CACHE" MIRRORS="$MIRRORS" MARKETPLACES="$MARKETPLACES" \
  INVENTORY="$INVENTORY" PATCHES="$PATCHES" PLUGINS_JSON="$PLUGINS_JSON" \
    bash "${BASH_SOURCE[0]}" --clean --dry-run extra >/dev/null 2>&1 || crc=$?
  [ "$crc" = 2 ] || { echo "self-test FAIL: a third argument to --clean was not refused" >&2; return 1; }
  SKILLS_DIR="$SKILLS_DIR" PLUGIN_CACHE="$PLUGIN_CACHE" MIRRORS="$MIRRORS" MARKETPLACES="$MARKETPLACES" \
  INVENTORY="$INVENTORY" PATCHES="$PATCHES" PLUGINS_JSON="$PLUGINS_JSON" \
    bash "${BASH_SOURCE[0]}" --clean --dry-run >/dev/null 2>&1 \
    || { echo "self-test FAIL: --clean --dry-run no longer succeeds" >&2; return 1; }

  # --- --check refuses a missing skills root -------------------------------------------------------
  # lint already refused; check misclassified instead - every row not-vendored/BLOCKED, a
  # fleet-wide-loss reading. Asserted through a child run like the --clean world: it keeps the
  # refusal's nonzero exit out of this function's set -e context without an if/case wrapper.
  crc=0
  SKILLS_DIR="$root/absent-skills" PLUGIN_CACHE="$PLUGIN_CACHE" MIRRORS="$MIRRORS" MARKETPLACES="$MARKETPLACES" \
  INVENTORY="$INVENTORY" PATCHES="$PATCHES" PLUGINS_JSON="$PLUGINS_JSON" \
    bash "${BASH_SOURCE[0]}" --check >/dev/null 2>"$root/check-missing.err" || crc=$?
  [ "$crc" -ne 0 ] \
    || { echo "self-test FAIL: --check exited 0 on a missing skills directory" >&2; return 1; }
  grep -q 'check: no skills directory at' "$root/check-missing.err" \
    || { echo "self-test FAIL: --check refusal message missing" >&2; return 1; }

  # --- a flat-layout leftover beside the script warns, and stops warning once deleted --------------
  # The guard keys on the invoked script's own dir, not on env - so the fixture runs a copy of the
  # script from $root/flat/scripts (planting artifacts beside the real script would dirty the tree
  # CI tests). All three probe shapes are planted: a warning count of 3 pins every probe string,
  # so a typo in any one of them cannot pass. Warn-only: exit stays 0, warnings live on stderr.
  mkdir -p "$root/flat/scripts/scripts"
  cp "${BASH_SOURCE[0]}" "$root/flat/scripts/resync.sh"
  cp "${BASH_SOURCE[0]}" "$root/flat/resync.sh"
  cp "$INVENTORY" "$root/flat/inventory.tsv"
  crc=0
  SKILLS_DIR="$SKILLS_DIR" PLUGIN_CACHE="$PLUGIN_CACHE" MIRRORS="$MIRRORS" MARKETPLACES="$MARKETPLACES" \
  INVENTORY="$INVENTORY" PATCHES="$PATCHES" PLUGINS_JSON="$PLUGINS_JSON" \
    bash "$root/flat/scripts/resync.sh" --check >/dev/null 2>"$root/flat.err" || crc=$?
  [ "$crc" = 0 ] \
    || { echo "self-test FAIL: flat-layout warning changed the exit status" >&2; return 1; }
  [ "$(grep -c 'legacy flat-layout leftover' "$root/flat.err")" = 3 ] \
    || { echo "self-test FAIL: expected 3 flat-layout warnings, got $(grep -c 'legacy flat-layout leftover' "$root/flat.err")" >&2; return 1; }
  rm "$root/flat/inventory.tsv" "$root/flat/resync.sh"
  rmdir "$root/flat/scripts/scripts"
  crc=0
  SKILLS_DIR="$SKILLS_DIR" PLUGIN_CACHE="$PLUGIN_CACHE" MIRRORS="$MIRRORS" MARKETPLACES="$MARKETPLACES" \
  INVENTORY="$INVENTORY" PATCHES="$PATCHES" PLUGINS_JSON="$PLUGINS_JSON" \
    bash "$root/flat/scripts/resync.sh" --check >/dev/null 2>"$root/flat2.err" || crc=$?
  [ "$crc" = 0 ] \
    || { echo "self-test FAIL: clean flat-layout run failed" >&2; return 1; }
  grep -q 'legacy flat-layout leftover' "$root/flat2.err" \
    && { echo "self-test FAIL: warning survived the deletion" >&2; return 1; }
  # The real script's own tree is what CI runs on: it must stay warning-free.
  case "$(check 2>&1 >/dev/null)" in *'legacy flat-layout leftover'*)
    echo "self-test FAIL: the guard fires on this script's own clean tree" >&2; return 1 ;; esac

  echo "self-test OK"
}

usage() { sed -n '/^# Usage:/,/^set -/p' "${BASH_SOURCE[0]}" | sed -n 's/^# \?//p'; }

case "${1:---help}" in
  --refresh)   refresh ;;
  --check)     check ;;
  --lint)      lint ;;
  --diff)      [ $# -eq 2 ] || { usage; exit 2; }
               row=$(lookup "$2") || { echo "$2: not in inventory.tsv" >&2; exit 1; }
               up=$(cut -d"$US" -f5 <<<"$row"); note=$(cut -d"$US" -f7 <<<"$row"); live=$(cut -d"$US" -f8 <<<"$row")
               [ -z "$note" ] || { echo "$2: ${note%%|*} - ${note#*|}" >&2; exit 1; }
               drift_diff "$up" "$live" ;;
  --snapshot)  shift; [ $# -gt 0 ] || { usage; exit 2; }; snapshot "$@" ;;
  --apply)     shift; [ $# -gt 0 ] || { usage; exit 2; }; apply "$@" ;;
  --hash)      [ $# -eq 2 ] || { usage; exit 2; }; py_helper hash "$2" ;;
  --clean)     [ $# -le 2 ] || { usage; exit 2; }
               case ${2:-} in
                 '')        clean ;;
                 --dry-run) clean --dry-run ;;
                 *)         usage; exit 2 ;;
               esac ;;
  --self-test) self_test ;;
  -h|--help)   usage ;;
  *)           usage; exit 2 ;;
esac
