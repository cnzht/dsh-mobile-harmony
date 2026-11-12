'use strict';
// Entry point so `node --test tests/` works on Node builds that do not
// expand a directory argument (this machine's Node 24.22.1 tries to load
// the directory as a module instead). Node resolves the directory to
// this file and runs it as a test file; requiring each *.test.js here
// registers all of their tests in this process.
//
// `node --test "tests/**" + "/*.test.js"` (one glob) also works and runs
// each file in its own process. Either way, do not put tests in this
// file — add a new *.test.js next to it and it is picked up automatically.
const fs = require('node:fs');
const path = require('node:path');

for (const file of fs.readdirSync(__dirname).sort()) {
  if (/\.test\.js$/.test(file)) {
    require(path.join(__dirname, file));
  }
}
