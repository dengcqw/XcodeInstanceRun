#!/bin/bash
make release

echo "Installing to /usr/local/bin"
ditto .build/release/XcodeInstanceRun /usr/local/bin/XcodeInstanceRun
