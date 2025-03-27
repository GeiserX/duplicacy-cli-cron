#!/bin/sh
MY-LOCATION=...
MY-SECOND-LOCATION=...

cd /local_shares/${MY-LOCATION}
rm -rf .duplicacy/

cd /local_shares/${MY-SECOND-LOCATION}
rm -rf .duplicacy/

...