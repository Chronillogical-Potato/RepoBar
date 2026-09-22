import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

for (const configuration of ['debug', 'release']) {
  for (const skipBuild of [false, true]) {
    test(`package_app ${configuration}, skip build: ${skipBuild}`, (t) => {
      const root = mkdtempSync(join(tmpdir(), 'repobar-package-'));
      t.after(() => rmSync(root, { recursive: true, force: true }));
      mkdirSync(join(root, 'Scripts'));
      mkdirSync(join(root, 'bin'));
      copyFileSync(new URL('./package_app.sh', import.meta.url), join(root, 'Scripts/package_app.sh'));
      writeFileSync(join(root, 'version.env'), 'MARKETING_VERSION=0.0.0\nBUILD_NUMBER=0\n');
      const calls = join(root, 'swift-calls');
      writeFileSync(calls, '');
      writeFileSync(join(root, 'bin/swift'), '#!/bin/sh\nprintf "%s\\n" "$@" --call-- >> "$SWIFT_CALLS"\n', { mode: 0o755 });

      const result = spawnSync('/bin/bash', [join(root, 'Scripts/package_app.sh'), configuration], {
        encoding: 'utf8',
        env: { ...process.env, PATH: `${join(root, 'bin')}:${process.env.PATH}`, SWIFT_CALLS: calls, SKIP_BUILD: skipBuild ? '1' : '0' },
      });
      // Stop before bundle assembly; this fixture deliberately has no build products.
      assert.equal(result.status, 1);
      assert.equal(result.stderr.trim(), `ERROR: Build dir not found: ${root}/.build/${configuration}`);
      const architecture = configuration === 'release' ? ['--arch', 'arm64', '--arch', 'x86_64'] : [];
      const expected = skipBuild ? [] : [
        'build', '-c', configuration, ...architecture, '--call--',
        'build', '-c', configuration, ...architecture, '--product', 'repobarcli', '--call--',
      ];
      assert.equal(readFileSync(calls, 'utf8'), expected.length ? `${expected.join('\n')}\n` : '');
    });
  }
}
