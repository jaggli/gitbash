#!/usr/bin/env node
// npm entry point: runs bin/gitbash with bash.
// On Windows, npm's own launchers would run the first bash on PATH, which is
// often WSL's (C:\Windows\System32\bash.exe): use Git for Windows' bash instead.
'use strict';

var childProcess = require('child_process');
var fs = require('fs');
var path = require('path');

// Forward slashes: bash's dirname doesn't split C:\...\bin\gitbash
var script = path.join(__dirname, 'gitbash').replace(/\\/g, '/');

function isFile(file) {
    try {
        return fs.statSync(file).isFile();
    } catch (e) {
        return false;
    }
}

// <Git>\bin\bash.exe: it puts git and the Unix tools on PATH, unlike usr\bin\bash.exe
function bashIn(root) {
    var bash = root && path.join(root, 'bin', 'bash.exe');
    return bash && isFile(bash) ? bash : null;
}

function gitForWindowsBash() {
    var dirs = (process.env.PATH || '').split(path.delimiter);
    var i, dir, bash;
    // git.exe is in <Git>\cmd, <Git>\bin or <Git>\mingw64\bin
    for (i = 0; i < dirs.length; i++) {
        dir = dirs[i].replace(/^"|"$/g, '');
        if (dir && isFile(path.join(dir, 'git.exe'))) {
            bash = bashIn(path.dirname(dir)) || bashIn(path.dirname(path.dirname(dir)));
            if (bash) return bash;
        }
    }
    var keys = ['HKLM\\SOFTWARE\\GitForWindows', 'HKCU\\SOFTWARE\\GitForWindows'];
    for (i = 0; i < keys.length; i++) {
        var out = childProcess.spawnSync('reg', ['query', keys[i], '/v', 'InstallPath'], { encoding: 'utf8' });
        var match = /InstallPath\s+REG_SZ\s+(.+)/.exec(out.stdout || '');
        bash = match && bashIn(match[1].trim());
        if (bash) return bash;
    }
    var roots = [
        process.env.ProgramFiles && path.join(process.env.ProgramFiles, 'Git'),
        process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, 'Programs', 'Git')
    ];
    for (i = 0; i < roots.length; i++) {
        bash = bashIn(roots[i]);
        if (bash) return bash;
    }
    return null;
}

var bash = 'bash';
if (process.platform === 'win32') {
    bash = gitForWindowsBash();
    if (!bash) {
        process.stderr.write('gitbash needs Git for Windows. Install it with: winget install Git.Git\n');
        process.exit(1);
    }
}

var child = childProcess.spawn(bash, [script].concat(process.argv.slice(2)), { stdio: 'inherit' });

// Ctrl-C (SIGINT, SIGQUIT) reaches bash and fzf directly from the terminal: wait
// for them instead of exiting first. SIGTERM and SIGHUP are passed on.
var handlers = {};
['SIGINT', 'SIGQUIT', 'SIGTERM', 'SIGHUP'].forEach(function (signal) {
    handlers[signal] = signal === 'SIGTERM' || signal === 'SIGHUP'
        ? function () { child.kill(signal); }
        : function () {};
    try {
        process.on(signal, handlers[signal]);
    } catch (e) {
        // Not supported on this platform
    }
});

child.on('error', function (err) {
    process.stderr.write('gitbash: could not run ' + bash + ': ' + err.message + '\n');
    process.exit(1);
});

child.on('exit', function (code, signal) {
    if (signal) {
        // Exit the same way bash did
        Object.keys(handlers).forEach(function (s) {
            process.removeListener(s, handlers[s]);
        });
        process.kill(process.pid, signal);
        return;
    }
    process.exit(code === null ? 1 : code);
});
