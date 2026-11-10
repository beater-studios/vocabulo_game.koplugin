#!/bin/sh
# Builds the plugin zip in dist/, with its checksum.
set -eu
. "$(dirname "$0")/package_lib.sh"
package_start "vocabulo_game"
package_stage
package_add data assets
package_zip
