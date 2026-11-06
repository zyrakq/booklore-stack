#!/bin/sh
# s3fs-fuse extension entrypoint (booklore stack).
# Mounts the RustFS buckets at /books + /bookdrop via s3fs, then execs
# the service's original entrypoint (/usr/local/bin/entrypoint.sh), which
# does the USER_ID/GROUP_ID remap and su-exec's down to the booklore
# user. Credentials are supplied through environment variables only and
# written to 0600 passwd files at start; they are never logged.
# /app/data and the MariaDB volume are NEVER mounted via s3fs.
set -euf

: "${S3FS_ENDPOINT:=http://rustfs:9000}"
: "${S3FS_BOOKS_BUCKET:?S3FS_BOOKS_BUCKET is required}"
: "${S3FS_BOOKDROP_BUCKET:?S3FS_BOOKDROP_BUCKET is required}"
: "${S3FS_ARGS:=}"
: "${USER_ID:=1000}"
: "${GROUP_ID:=1000}"

: "${RUSTFS_ACCESS_KEY:?RUSTFS_ACCESS_KEY is required}"
: "${RUSTFS_SECRET_KEY:?RUSTFS_SECRET_KEY is required}"

umask 077
BOOKS_PASSWD="/tmp/.s3fs-passwd-${S3FS_BOOKS_BUCKET}"
BOOKDROP_PASSWD="/tmp/.s3fs-passwd-${S3FS_BOOKDROP_BUCKET}"
printf '%s:%s\n' "$RUSTFS_ACCESS_KEY" "$RUSTFS_SECRET_KEY" > "$BOOKS_PASSWD"
printf '%s:%s\n' "$RUSTFS_ACCESS_KEY" "$RUSTFS_SECRET_KEY" > "$BOOKDROP_PASSWD"

# The base compose still mounts the local booklore-books/booklore-bookdrop
# volumes at /books + /bookdrop (stackbuilder merges volume lists
# append-only); drop them so the buckets are the only library sources,
# then mount s3fs over the mountpoints. uid/gid + allow_other so the
# unprivileged booklore user (su-exec'd by the original entrypoint) can
# read/write the mounts.
umount /books 2>/dev/null || true
umount /bookdrop 2>/dev/null || true

s3fs "$S3FS_BOOKS_BUCKET" /books \
  -o passwd_file="$BOOKS_PASSWD" \
  -o url="$S3FS_ENDPOINT" \
  -o use_path_request_style \
  -o connect_timeout=30 \
  -o readwrite_timeout=120 \
  -o uid="$USER_ID" -o gid="$GROUP_ID" -o allow_other \
  $S3FS_ARGS

s3fs "$S3FS_BOOKDROP_BUCKET" /bookdrop \
  -o passwd_file="$BOOKDROP_PASSWD" \
  -o url="$S3FS_ENDPOINT" \
  -o use_path_request_style \
  -o connect_timeout=30 \
  -o readwrite_timeout=120 \
  -o uid="$USER_ID" -o gid="$GROUP_ID" -o allow_other \
  $S3FS_ARGS

# s3fs can return before the mounts are fully live; wait for both.
wait_mount() {
  i=0
  while ! awk -v m="$1" '$2 == m && $3 ~ /^fuse/ { f = 1 } END { exit !f }' /proc/mounts; do
    i=$((i + 1))
    if [ "$i" -ge 30 ]; then
      echo "s3fs: mount $1 did not come up within 30s" >&2
      exit 1
    fi
    sleep 1
  done
}
wait_mount /books
wait_mount /bookdrop

# Exec the original entrypoint unchanged (USER_ID/GROUP_ID remap +
# su-exec booklore).
exec "$@"
