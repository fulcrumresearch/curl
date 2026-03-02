# Verification: API failure silent fallback (identified issue)

## Issue

When `-r` is used but the GitHub API call to retrieve the commit timestamp fails
(network error, rate limit, timeout), the script silently falls back to using
`stat()` on the downloaded file or `time()`. This produces non-deterministic output
without any warning or error.

The PR's own TODO acknowledges this: "fail if the stable timestamp could not be
determined, and thus the output is not reproducible." But this is not implemented.

## How to reproduce

Create a curl wrapper that simulates API failure:

```bash
mkdir -p /tmp/fakebin
cat > /tmp/fakebin/curl << 'EOF'
#!/bin/bash
for arg in "$@"; do
    if [[ "$arg" == *"api.github.com"* ]]; then
        echo "curl: (28) Connection timed out" >&2
        exit 28
    fi
done
exec /usr/bin/curl "$@"
EOF
chmod +x /tmp/fakebin/curl
```

Run the script with the fake curl in PATH:

```bash
WORKDIR=$(mktemp -d) && cd "$WORKDIR"
PATH="/tmp/fakebin:$PATH" perl /path/to/scripts/mk-ca-bundle.pl \
    -r 397c3187280dfa84ce9da56a9944d945bf73977d
```

## Expected behavior

The script should fail with an error message indicating the timestamp could not
be determined, since deterministic output was requested via `-r`.

## Actual behavior

The script succeeds (exit 0) and produces `ca-bundle.crt` with a non-deterministic
timestamp:

```
## Certificate data from Mozilla as of: <current date/time> GMT
```

The header says "as of" (non-deterministic) instead of "last updated on" (deterministic
from the commit). The file's mtime is the current time, not the commit time.

## Code location

`scripts/mk-ca-bundle.pl` lines 389-422. The fallback at line 414 (`if(!$filedate)`)
silently uses `stat()` or `time()` without checking whether `-r` mode requires a
stable timestamp.
