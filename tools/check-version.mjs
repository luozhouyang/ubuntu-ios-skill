#!/usr/bin/env node
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'))
const skillMd = readFileSync(
  join(root, 'skills', 'ubuntu-ios', 'SKILL.md'),
  'utf8',
)

const frontmatter = skillMd.match(/^---\r?\n([\s\S]*?)\r?\n---/)
if (!frontmatter) {
  console.error('error: skills/ubuntu-ios/SKILL.md has no YAML frontmatter')
  process.exit(1)
}

const block = frontmatter[1]
const name = block.match(/^name:\s*"?([^"\r\n]+?)"?\s*$/m)?.[1]
const version = block.match(
  /^metadata:[ \t]*\r?\n(?:[ \t]+[^\r\n]*\r?\n)*?[ \t]+version:\s*"?([^"\r\n]+?)"?\s*$/m,
)?.[1]

const errors = []
if (name !== 'ubuntu-ios') {
  errors.push(
    `SKILL.md name is ${JSON.stringify(name)}, expected "ubuntu-ios"`,
  )
}
if (version !== pkg.version) {
  errors.push(
    `SKILL.md metadata.version is ${JSON.stringify(version)}, package.json version is ${JSON.stringify(pkg.version)}`,
  )
}
if (pkg.name !== 'ubuntu-ios-skill') {
  errors.push(
    `package.json name is ${JSON.stringify(pkg.name)}, expected "ubuntu-ios-skill"`,
  )
}

if (errors.length > 0) {
  for (const error of errors) console.error(`error: ${error}`)
  process.exit(1)
}

console.log(
  `ok: ${pkg.name}@${pkg.version} <-> skills/ubuntu-ios (${name}@${version})`,
)
