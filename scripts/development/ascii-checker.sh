#!/usr/bin/env bash
#
# ascii-checker.sh - reject non-ASCII and invisible/control characters.
#
# Non-ASCII characters break grep-based code search and render badly in some
# terminals and log viewers. Invisible and bidirectional (BiDi) characters can
# also make source code look different to a reviewer than to a compiler or
# shell ("Trojan Source", CVE-2021-42574 and CVE-2021-42694).
#
# See usage() for the interface. Requires bash and Python 3.7+ (standard
# library only), found as python3 or python.

set -euo pipefail

# Keep the bash part portable to macOS (bash 3.2, BSD tools): no bash 4
# features, and expand arrays that may be empty as ${arr[@]+"${arr[@]}"}, since
# bash before 4.4 treats an empty "${arr[@]}" as unbound under set -u.

SCRIPT_NAME=ascii-checker.sh
SCRIPT_SOURCE=${BASH_SOURCE[0]:-}
if [[ -f ${SCRIPT_SOURCE} ]]; then
	# Run from a checkout: relaxed patterns are relative to the repository that
	# contains this script.
	SCRIPT_DIR=$(cd -- "$(dirname -- "${SCRIPT_SOURCE}")" && pwd -P)
	REPO_ROOT=$(cd -- "${SCRIPT_DIR}/../.." && pwd -P)
	DEFAULT_RELAXED_FROM="${SCRIPT_DIR}/ascii-checker-relaxed-paths.txt"
else
	# Launched from a URL, e.g. bash <(curl -fsSL .../ascii-checker.sh): use the
	# current repository and load no relaxed patterns unless -r is given.
	REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
	DEFAULT_RELAXED_FROM=''
fi

usage() {
	local relaxed_default=none
	if [[ -n ${DEFAULT_RELAXED_FROM} ]]; then
		relaxed_default=${DEFAULT_RELAXED_FROM#"${REPO_ROOT}/"}
	fi
	cat <<EOF
Usage:
  ${SCRIPT_NAME} [options] [--] FILE...
  ${SCRIPT_NAME} [options] -f LIST_FILE [-f LIST_FILE...] [FILE...]
  ${SCRIPT_NAME} [options] -

Check text for characters outside printable ASCII. Only TAB, LF, CRLF line
endings, and 0x20-0x7E are allowed.

Inputs:
  FILE...                Files to check.
  -f, --file-list FILE   Read file paths from FILE, one per line. Use "-f -"
                         to read the list from stdin (e.g. git diff --name-only).
  -                      Check the content of stdin instead of files. Must be
                         the only input.

Options:
  -d, --dangerous-only   Report only dangerous characters: BiDi controls,
                         zero-width and other default-ignorable (invisible)
                         characters, Unicode tag and variation-selector
                         smuggling, and ASCII/C1 control characters. Other
                         non-ASCII text is allowed.
  -c, --commit-message   Check commit messages: strict everywhere except
                         identity trailers (Signed-off-by, Co-authored-by, ...)
                         in paragraphs made only of trailer lines, other than
                         the subject paragraph. Those are checked with
                         --dangerous-only so that contributor names with
                         accents are accepted.
  -r, --relaxed-from F   Glob patterns (relative to the repository root) of
                         files that are checked with --dangerous-only.
                         Default: ${relaxed_default}
      --no-relaxed       Do not load relaxed path patterns.
  -l, --label NAME       Name used for stdin in reports (default: <stdin>).
  -h, --help             Show this help.

File names are checked with the same rules as file content. The content of
binary files (containing NUL bytes and invalid UTF-8) and symbolic links is
skipped with a warning. When GITHUB_ACTIONS=true, findings are printed as
GitHub workflow annotations.

Exit status: 0 no violations, 1 violations found, 2 usage or I/O error.

Examples:
  ${SCRIPT_NAME} README.md chart/values.yaml
  git diff --name-only --diff-filter=ACMR origin/master... | ${SCRIPT_NAME} -f -
  git log --format=%B%n origin/master..HEAD | ${SCRIPT_NAME} --commit-message -
EOF
}

usage_error() {
	echo "${SCRIPT_NAME}: $*" >&2
	echo "Try '${SCRIPT_NAME} --help' for more information." >&2
	exit 2
}

need_arg() {
	[[ $# -ge 2 ]] || usage_error "option '$1' requires an argument"
}

mode=strict
label='<stdin>'
relaxed_from=${DEFAULT_RELAXED_FROM}
stdin_content=false
list_files=()
files=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	-f | --file-list)
		need_arg "$@"
		list_files+=("$2")
		shift 2
		;;
	-d | --dangerous-only)
		mode=dangerous
		shift
		;;
	-c | --commit-message)
		mode=commit
		shift
		;;
	-r | --relaxed-from)
		need_arg "$@"
		relaxed_from=$2
		shift 2
		;;
	--no-relaxed)
		relaxed_from=''
		shift
		;;
	-l | --label)
		need_arg "$@"
		label=$2
		shift 2
		;;
	--)
		shift
		files+=("$@")
		break
		;;
	-)
		stdin_content=true
		shift
		;;
	-?*)
		usage_error "unknown option '$1'"
		;;
	*)
		files+=("$1")
		shift
		;;
	esac
done

if [[ ${stdin_content} == true ]]; then
	if [[ ${#files[@]} -gt 0 || ${#list_files[@]} -gt 0 ]]; then
		usage_error "'-' (check stdin) cannot be combined with other inputs"
	fi
elif [[ ${#files[@]} -eq 0 && ${#list_files[@]} -eq 0 ]]; then
	usage_error "no input given"
fi

# With "curl ... | bash -s", bash reads this script from stdin, so stdin cannot
# also carry a file list or text to check. Fail instead of checking nothing.
uses_stdin=${stdin_content}
for list_file in ${list_files[@]+"${list_files[@]}"}; do
	if [[ ${list_file} == - ]]; then
		uses_stdin=true
	fi
done
if [[ ${uses_stdin} == true && -z ${SCRIPT_SOURCE} ]]; then
	usage_error "stdin is already used to read this script; run 'bash <(curl -fsSL URL) ...' instead of 'curl -fsSL URL | bash -s -- ...'"
fi
stdin_list_used=false
for list_file in ${list_files[@]+"${list_files[@]}"}; do
	if [[ ${list_file} == - ]]; then
		[[ ${stdin_list_used} == false ]] || usage_error "'-f -' can be given only once"
		stdin_list_used=true
		list_file=/dev/stdin
	elif [[ ! -f ${list_file} || ! -r ${list_file} ]]; then
		usage_error "cannot read file list '${list_file}'"
	fi
	while IFS= read -r path || [[ -n ${path} ]]; do
		[[ -n ${path} ]] && files+=("${path}")
	done <"${list_file}"
done

if [[ -n ${relaxed_from} && ! -r ${relaxed_from} ]]; then
	if [[ ${relaxed_from} == "${DEFAULT_RELAXED_FROM}" ]]; then
		relaxed_from=''
	else
		usage_error "cannot read relaxed path patterns '${relaxed_from}'"
	fi
fi

if [[ ${stdin_content} == false && ${#files[@]} -eq 0 ]]; then
	echo "${SCRIPT_NAME}: no files to check" >&2
	exit 0
fi

find_python() {
	local candidate
	for candidate in python3 python; do
		if command -v "${candidate}" >/dev/null 2>&1 &&
			"${candidate}" -I -c 'import sys; sys.exit(sys.version_info < (3, 7))' >/dev/null 2>&1; then
			echo "${candidate}"
			return 0
		fi
	done
	return 1
}

PYTHON=$(find_python) || {
	echo "${SCRIPT_NAME}: Python 3.7 or later is required (python3 or python)" >&2
	exit 2
}

read -r -d '' PY_PROG <<'PY' || true
import os
import re
import signal
import sys
import unicodedata

MODE = os.environ["AC_MODE"]
LABEL = os.environ["AC_LABEL"]
USE_STDIN = os.environ["AC_STDIN"] == "true"
ROOT = os.environ["AC_ROOT"]
RELAXED_FROM = os.environ.get("AC_RELAXED", "")
GITHUB = os.environ.get("GITHUB_ACTIONS", "") == "true"

# Keep findings and the stderr summary in order when both go to a terminal.
sys.stdout.reconfigure(line_buffering=True)

# Exit quietly when the reader goes away, e.g. when piped into head.
if hasattr(signal, "SIGPIPE"):
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

# A line made only of TAB and printable ASCII needs no further checks.
CLEAN_LINE = re.compile(rb"[\t\x20-\x7e]*")

# Unicode Default_Ignorable_Code_Point (DerivedCoreProperties.txt, Unicode
# 18.0): characters that render as nothing, including reserved code points in
# these ranges. Other format characters (category Cf) are rejected as well.
DEFAULT_IGNORABLE = (
    (0x00AD, 0x00AD), (0x034F, 0x034F), (0x061C, 0x061C), (0x115F, 0x1160),
    (0x17B4, 0x17B5), (0x180B, 0x180F), (0x200B, 0x200F), (0x202A, 0x202E),
    (0x2060, 0x206F), (0x3164, 0x3164), (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF),
    (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3), (0x1D173, 0x1D17A),
    (0xE0000, 0xE0FFF),
)
LINE_SEPARATORS = {0x2028, 0x2029}

# Non-ASCII bases of the emoji variation sequences in Unicode
# emoji-variation-sequences.txt (18.0). U+FE0E and U+FE0F are accepted only
# directly after one of these; every other variation selector is rejected.
EMOJI_VARIATION_BASES = tuple(
    (int(lo, 16), int(hi or lo, 16))
    for lo, _, hi in (token.partition("-") for token in """
    00A9 00AE 203C 2049 2122 2139 2194-2199 21A9-21AA 231A-231B 2328 23CF
    23E9-23F3 23F8-23FA 24C2 25AA-25AB 25B6 25C0 25FB-25FE 2600-2604 260E 2611
    2614-2615 2618 261D 2620 2622-2623 2626 262A 262E-262F 2638-263A 2640 2642
    2648-2653 265F-2660 2663 2665-2666 2668 267B 267E-267F 2692-2697 2699
    269B-269C 26A0-26A1 26A7 26AA-26AB 26B0-26B1 26BD-26BE 26C4-26C5 26C8
    26CE-26CF 26D1 26D3-26D4 26E9-26EA 26F0-26F5 26F7-26FA 26FD 2702 2705
    2708-270D 270F 2712 2714 2716 271D 2721 2728 2733-2734 2744 2747 274C 274E
    2753-2755 2757 2763-2764 2795-2797 27A1 27B0 27BF 2934-2935 2B05-2B07
    2B1B-2B1C 2B50 2B55 3030 303D 3297 3299 1F004 1F170-1F171 1F17E-1F17F
    1F202 1F21A 1F22F 1F237 1F30D-1F30F 1F315 1F31C 1F321 1F324-1F32C 1F336
    1F378 1F37D 1F393 1F396-1F397 1F399-1F39B 1F39E-1F39F 1F3A7 1F3AC-1F3AE
    1F3C2 1F3C4 1F3C6 1F3CA-1F3CE 1F3D4-1F3E0 1F3ED 1F3F3 1F3F5 1F3F7 1F408
    1F415 1F41F 1F426 1F43F 1F441-1F442 1F446-1F449 1F44D-1F44E 1F453 1F46A
    1F47D 1F4A3 1F4B0 1F4B3 1F4BB 1F4BF 1F4CB 1F4DA 1F4DF 1F4E4-1F4E6
    1F4EA-1F4ED 1F4F7 1F4F9-1F4FB 1F4FD 1F508 1F50D 1F512-1F513 1F549-1F54A
    1F550-1F567 1F56F-1F570 1F573-1F579 1F587 1F58A-1F58D 1F590 1F5A5 1F5A8
    1F5B1-1F5B2 1F5BC 1F5C2-1F5C4 1F5D1-1F5D3 1F5DC-1F5DE 1F5E1 1F5E3 1F5E8
    1F5EF 1F5F3 1F5FA 1F610 1F687 1F68D 1F691 1F694 1F698 1F6AD 1F6B2
    1F6B9-1F6BA 1F6BC 1F6CB 1F6CD-1F6CF 1F6E0-1F6E5 1F6E9 1F6F0 1F6F3
""".split())
)

# Identity trailers whose values may hold contributor names.
IDENTITY_TRAILER = re.compile(
    rb"(?i)(?:Signed-off-by|Co-authored-by|Acked-by|Reviewed-by|Tested-by"
    rb"|Reported-by|Suggested-by|Helped-by):[ \t]"
)
# Any git trailer line ("Token: value") or a folded continuation line.
TRAILER_LINE = re.compile(rb"[A-Za-z0-9][A-Za-z0-9-]*:[ \t]|[ \t]+\S")

HINTS = {}
for cps, hint in (
    ((0x2010, 0x2011, 0x2012, 0x2013, 0x2212, 0x2500, 0x2501), "-"),
    ((0x2014, 0x2015), "--"),
    ((0x2018, 0x2019, 0x201A, 0x201B, 0x2032), "'"),
    ((0x201C, 0x201D, 0x201E, 0x201F, 0x2033), '"'),
    ((0x2502, 0x2503), "|"),
    ((0x250C, 0x2510, 0x2514, 0x2518, 0x251C, 0x2524, 0x252C, 0x2534, 0x253C), "+"),
    ((0x2022, 0x00B7), "*"),
    ((0x2705, 0x2713, 0x2714), "yes"),
):
    for cp in cps:
        HINTS[cp] = hint
HINTS.update({
    0x00A0: " ", 0x2026: "...", 0x00D7: "x", 0x00B1: "+/-",
    0x2190: "<-", 0x2192: "->", 0x2194: "<->", 0x21D0: "<=",
    0x21D2: "=>", 0x2264: "<=", 0x2265: ">=", 0x2260: "!=",
    0x26A0: "WARNING", 0x1F517: "link",
})

# unicodedata has no names for control characters; use their Unicode aliases.
C0_NAMES = (
    "NULL", "START OF HEADING", "START OF TEXT", "END OF TEXT",
    "END OF TRANSMISSION", "ENQUIRY", "ACKNOWLEDGE", "ALERT", "BACKSPACE",
    "CHARACTER TABULATION", "LINE FEED", "LINE TABULATION", "FORM FEED",
    "CARRIAGE RETURN", "SHIFT OUT", "SHIFT IN", "DATA LINK ESCAPE",
    "DEVICE CONTROL ONE", "DEVICE CONTROL TWO", "DEVICE CONTROL THREE",
    "DEVICE CONTROL FOUR", "NEGATIVE ACKNOWLEDGE", "SYNCHRONOUS IDLE",
    "END OF TRANSMISSION BLOCK", "CANCEL", "END OF MEDIUM", "SUBSTITUTE",
    "ESCAPE", "INFORMATION SEPARATOR FOUR", "INFORMATION SEPARATOR THREE",
    "INFORMATION SEPARATOR TWO", "INFORMATION SEPARATOR ONE",
)

violations = 0
errors = 0
checked = 0


def is_variation_selector(cp):
    return 0xFE00 <= cp <= 0xFE0F


def is_dangerous(text, i):
    """Dangerous characters are rejected in every mode, including relaxed
    paths and commit message trailers."""
    cp = ord(text[i])
    if cp < 0x20:
        # ASCII control characters. CR is allowed only in a CRLF line ending,
        # which check_line() strips before scanning.
        return cp != 0x09
    if 0x7F <= cp <= 0x9F:
        return True
    if is_variation_selector(cp):
        # Only a text or emoji presentation selector on a listed emoji base.
        if cp not in (0xFE0E, 0xFE0F) or i == 0:
            return True
        prev = ord(text[i - 1])
        return not any(lo <= prev <= hi for lo, hi in EMOJI_VARIATION_BASES)
    if cp in LINE_SEPARATORS or any(lo <= cp <= hi for lo, hi in DEFAULT_IGNORABLE):
        return True
    return unicodedata.category(text[i]) == "Cf"


def is_violation(text, i, mode):
    if mode == "strict":
        cp = ord(text[i])
        return not (cp == 0x09 or 0x20 <= cp <= 0x7E)
    return is_dangerous(text, i)


def printable(text):
    """Render text as printable ASCII so that reports never carry the
    offending characters themselves."""
    return "".join(c if 0x20 <= ord(c) <= 0x7E else "<U+%04X>" % ord(c) for c in text)


def decode_prefix(data):
    """Decode UTF-8 strictly; return the valid prefix and the offset of the
    first invalid byte (None when the whole input is valid)."""
    try:
        return data.decode("utf-8"), None
    except UnicodeDecodeError as e:
        return data[:e.start].decode("utf-8"), e.start


def display_name(name):
    """File names and labels arrive as OS strings: decode what is valid UTF-8
    and show any remaining bytes in hex."""
    data = os.fsencode(name)
    text, bad = decode_prefix(data)
    rest = data[bad:] if bad is not None else b""
    return printable(text) + "".join(
        chr(b) if 0x20 <= b <= 0x7E else "<0x%02X>" % b for b in rest
    )


def gh_escape(text, is_property=False):
    text = text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    if is_property:
        text = text.replace(":", "%3A").replace(",", "%2C")
    return text


def report(level, name, is_file, line, col, msg):
    where = display_name(name) + (":%d:%d" % (line, col) if line is not None else "")
    if GITHUB:
        props = ["title=" + gh_escape("ASCII check", True)]
        if is_file:
            props.append("file=" + gh_escape(display_name(name), True))
            if line is not None:
                props += ["line=%d" % line, "col=%d" % col]
        print("::%s %s::%s" % (level, ",".join(props), gh_escape("%s: %s" % (where, msg))))
    elif level == "error":
        print("%s: %s" % (where, msg))
    else:
        print("%s: %s: %s" % (where, level, msg), file=sys.stderr)


def excerpt(text, col):
    start = col - 60 if col > 60 else 0
    piece = text[start:start + 140]
    more = len(text) > start + 140
    return "    | %s%s%s" % ("..." if start else "", printable(piece), "..." if more else "")


def char_name(cp):
    if cp < 0x20:
        return C0_NAMES[cp]
    if cp == 0x7F:
        return "DELETE"
    if 0x80 <= cp <= 0x9F:
        return "C1 CONTROL CHARACTER"
    return unicodedata.name(chr(cp), "UNNAMED CHARACTER")


def describe(cp, dangerous):
    desc = "U+%04X %s" % (cp, char_name(cp))
    if dangerous:
        return desc + ": invisible, BiDi, or control character (Trojan Source risk); remove it"
    msg = desc + ": non-ASCII character"
    if cp in HINTS:
        quote = "'" if '"' in HINTS[cp] else '"'
        msg += "; use %s%s%s instead" % (quote, HINTS[cp], quote)
    return msg


def check_name(path, mode):
    """A file name is part of the change too: check it with the same rules as
    the file content, reporting each offending character once."""
    global violations
    data = os.fsencode(path)
    text, bad = decode_prefix(data)
    found = 0
    if bad is not None:
        report("error", path, True, None, None,
               "file name has invalid UTF-8 byte sequence starting with byte 0x%02X" % data[bad])
        found += 1
    seen = set()
    for i, c in enumerate(text):
        if not is_violation(text, i, mode) or ord(c) in seen:
            continue
        seen.add(ord(c))
        dangerous = mode != "strict" or is_dangerous(text, i)
        report("error", path, True, None, None, "file name: " + describe(ord(c), dangerous))
        found += 1
    violations += found


def check_line(name, is_file, lineno, data, mode):
    global violations
    # Allow a CRLF line ending; any other CR is reported as a control character.
    if data.endswith(b"\r\n"):
        data = data[:-2]
    elif data.endswith(b"\n"):
        data = data[:-1]
    if CLEAN_LINE.fullmatch(data):
        return

    text, bad = decode_prefix(data)
    found = 0
    if bad is not None:
        report("error", name, is_file, lineno, len(text) + 1,
               "invalid UTF-8 byte sequence starting with byte 0x%02X" % data[bad])
        found += 1

    # Collapse runs of the same character into one finding: [cp, col, len, dangerous].
    runs = []
    for i, c in enumerate(text):
        if not is_violation(text, i, mode):
            continue
        cp = ord(c)
        if runs and runs[-1][0] == cp and runs[-1][1] - 1 + runs[-1][2] == i:
            runs[-1][2] += 1
            continue
        runs.append([cp, i + 1, 1, mode != "strict" or is_dangerous(text, i)])
    for cp, col, length, dangerous in runs:
        msg = describe(cp, dangerous)
        if length > 1:
            msg += " (x%d)" % length
        report("error", name, is_file, lineno, col, msg)
        found += 1

    if found:
        print(excerpt(text, runs[0][1] if runs else len(text) + 1))
        violations += found


def relaxed_trailer_lines(lines):
    """Return the indexes of identity trailer lines that may hold non-ASCII
    contributor names: those in a paragraph made only of trailer lines, other
    than the first (subject) paragraph. Besides the final trailer block, this
    covers the per-commit sign-offs that squashing leaves in the body; an
    identity-like line inside prose stays strict."""
    relaxed = set()
    start = None
    seen_paragraph = False
    for index, line in enumerate(lines + [b""]):
        if line.strip():
            if start is None:
                start = index
            continue
        if start is None:
            continue
        paragraph = range(start, index)
        if seen_paragraph and all(TRAILER_LINE.match(lines[i]) for i in paragraph):
            relaxed.update(i for i in paragraph if IDENTITY_TRAILER.match(lines[i]))
        seen_paragraph = True
        start = None
    return relaxed


def check_stream(stream, name, is_file, mode):
    global checked
    if mode == "commit":
        lines = stream.readlines()
        relaxed = relaxed_trailer_lines(lines)
        for index, line in enumerate(lines):
            check_line(name, is_file, index + 1, line, "dangerous" if index in relaxed else "strict")
    else:
        for lineno, line in enumerate(stream, 1):
            check_line(name, is_file, lineno, line, mode)
    checked += 1


def glob_to_re(glob):
    glob = glob.lstrip("/")
    if glob.endswith("/"):
        glob += "**"
    parts = []
    for token in re.findall(r"\*\*/|\*\*|\*|\?|[^*?]+", glob):
        if token == "**/":
            parts.append("(?:.*/)?")
        elif token == "**":
            parts.append(".*")
        elif token == "*":
            parts.append("[^/]*")
        elif token == "?":
            parts.append("[^/]")
        else:
            parts.append(re.escape(token))
    return re.compile("".join(parts) + r"\Z")


relaxed = []
if RELAXED_FROM:
    with open(RELAXED_FROM, encoding="utf-8") as patterns:
        for pattern in patterns:
            pattern = pattern.strip()
            if pattern and not pattern.startswith("#"):
                relaxed.append(glob_to_re(pattern))


def is_relaxed(path):
    if not relaxed:
        return False
    rel = os.path.relpath(os.path.abspath(path), ROOT)
    if rel == ".." or rel.startswith(".." + os.sep):
        return False
    return any(pattern.match(rel) for pattern in relaxed)


def is_binary(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if b"\0" not in data[:8000]:
        return False
    return decode_prefix(data)[1] is not None


if USE_STDIN:
    check_stream(sys.stdin.buffer, LABEL, False, MODE)
else:
    for path in sys.argv[1:]:
        path_relaxed = MODE == "dangerous" or is_relaxed(path)
        check_name(path, "dangerous" if path_relaxed else "strict")
        if os.path.islink(path):
            report("warning", path, True, None, None, "skipped (symbolic link)")
            continue
        if os.path.isdir(path):
            report("error", path, False, None, None, "is a directory")
            errors += 1
            continue
        try:
            fh = open(path, "rb")
        except OSError as e:
            report("error", path, False, None, None, "cannot open: %s" % e.strerror)
            errors += 1
            continue
        with fh:
            if is_binary(path):
                report("warning", path, True, None, None, "skipped (binary file)")
                continue
            input_mode = "dangerous" if MODE == "strict" and path_relaxed else MODE
            check_stream(fh, path, True, input_mode)

summary = "ascii-checker: %d input(s) checked, %d violation(s)" % (checked, violations)
if errors:
    summary += ", %d error(s)" % errors
print(summary, file=sys.stderr)
sys.exit(2 if errors else 1 if violations else 0)
PY

export AC_MODE=${mode}
export AC_LABEL=${label}
export AC_STDIN=${stdin_content}
export AC_ROOT=${REPO_ROOT}
export AC_RELAXED=${relaxed_from}

# -I (isolated mode) keeps PYTHON* variables, user site-packages, and modules
# in the current directory out of the checker.
if [[ ${stdin_content} == true ]]; then
	exec "${PYTHON}" -I -c "${PY_PROG}"
fi
exec "${PYTHON}" -I -c "${PY_PROG}" "${files[@]}"
