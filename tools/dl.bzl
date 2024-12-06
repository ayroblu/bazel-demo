def dl(ctx, url, filename, out, sha256):
    ctx.actions.run_shell(
        outputs = [out],
        arguments = [url, filename, out.path, sha256],
        command = """
        set -euo pipefail
        dl() {
          local url="$1"
          local temppath="$TMPDIR/dl/$2"
          local out="$3"
          local sha256="$4"

          [ ! -d "$TMPDIR/dl" ] && mkdir "$TMPDIR/dl"
          if [ ! -f "$temppath" ]; then
            echo "Downloading $url"
            curl -sfL "$url" -o "$temppath"
          fi
          # sha256sum for linux
          echo "$sha256  $temppath" | shasum -a 256 -s -c || {
            echo "Checksum did not match: $sha256  $temppath"
            exit 1
          }

          cp -c "$temppath" "$out"
        }
        dl "$1" "$2" "$3" "$4"
        """,
    )
