import { mkdir, mkdtemp, readFile, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { isAbsolute, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { unzipSync, zipSync } from 'fflate';

const root = await realpath(fileURLToPath(new URL('../', import.meta.url)));
const toc = 'QuestTidy.toc';
const versionPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

async function readAddonFile(name) {
  if (!name || name.includes(':') || isAbsolute(name) || name.split('/').includes('..')) {
    throw new Error(`Invalid addon path: ${name}`);
  }
  const source = await realpath(join(root, name));
  const location = relative(root, source);
  if (location === '..' || location.startsWith(`..${sep}`) || isAbsolute(location)) {
    throw new Error(`Addon path escapes the source folder: ${name}`);
  }
  return readFile(source);
}

async function packageAddon(outputDir, tag) {
  const tocContents = await readAddonFile(toc);
  const lines = tocContents.toString('utf8').replace(/^\uFEFF/, '').split(/\r?\n/).map(line => line.trim());
  const versions = lines.filter(line => /^##\s*Version:/.test(line));
  const version = versions[0]?.match(/^##\s*Version:\s*(\S+)$/)?.[1];
  if (versions.length !== 1 || !versionPattern.test(version ?? '')) {
    throw new Error(`${toc} must declare one X.Y.Z version`);
  }
  if (tag !== undefined && tag !== `v${version}`) {
    throw new Error(`Tag ${JSON.stringify(tag)} does not match ${toc}; expected v${version}`);
  }

  const listed = lines.filter(line => line && !line.startsWith('#')).map(line => line.replaceAll('\\', '/'));
  const names = [...new Set([toc, 'LICENSE', ...listed])].sort();
  const files = Object.fromEntries(await Promise.all(names.map(async name => [
    `QuestTidy/${name}`, name === toc ? tocContents : await readAddonFile(name),
  ])));
  const zip = zipSync(files, { mtime: new Date(1980, 0, 1) });
  const extracted = unzipSync(zip);
  if (Object.keys(extracted).length !== names.length || Object.entries(files).some(([name, bytes]) =>
    !extracted[name] || !bytes.equals(extracted[name]))) {
    throw new Error('ZIP verification failed');
  }

  await mkdir(outputDir, { recursive: true });
  const stage = await mkdtemp(join(outputDir, '.questtidy-'));
  const filename = `QuestTidy-${version}.zip`;
  const archive = join(outputDir, filename);
  try {
    const stagedArchive = join(stage, filename);
    await writeFile(stagedArchive, zip);
    await rename(stagedArchive, archive);
  } finally {
    await rm(stage, { recursive: true, force: true });
  }
  return archive;
}

try {
  const { values } = parseArgs({ options: {
    'output-dir': { type: 'string' },
    tag: { type: 'string' },
  } });
  const tag = values.tag ?? (process.env.GITHUB_REF_TYPE === 'tag' ? process.env.GITHUB_REF_NAME : undefined);
  console.log(await packageAddon(resolve(values['output-dir'] ?? join(root, 'dist')), tag));
} catch (error) {
  console.error(`Packaging failed: ${error.message}`);
  process.exitCode = 1;
}
