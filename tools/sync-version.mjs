#!/usr/bin/env node
import { execFileSync } from 'node:child_process'
import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
const skillPath = join(root, 'skills', 'ubuntu-ios', 'SKILL.md')
const skillMd = readFileSync(skillPath, 'utf8')

const pattern =
  /(^metadata:[ \t]*\r?\n(?:[ \t]+[^\r\n]*\r?\n)*?[ \t]+version:\s*)"[^"\r\n]*"/m
if (!pattern.test(skillMd)) {
  console.error('error: could not find metadata.version in skills/ubuntu-ios/SKILL.md')
  process.exit(1)
}

const updated = skillMd.replace(pattern, (match, prefix) => `${prefix}"${pkg.version}"`)
if (updated === skillMd) {
  console.log(`ok: SKILL.md already at ${pkg.version}`)
} else {
  writeFileSync(skillPath, updated)
  console.log(`ok: synced SKILL.md metadata.version to ${pkg.version}`)
}

try {
  execFileSync('git', ['add', skillPath], { cwd: root, stdio: 'ignore' })
} catch {
  // not a git checkout (e.g. an installed tarball)
}
