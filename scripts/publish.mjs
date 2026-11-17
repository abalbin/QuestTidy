import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, join, resolve } from 'node:path';

const { GH_REPO: repo, GITHUB_REF_NAME: tag, BUILD_COMMIT: commit } = process.env;

function gh(args) {
  return execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

function verifyTag() {
  const getObject = (path) => JSON.parse(gh(['api', `repos/${repo}/git/${path}`, '--jq', '.object']));
  let object = getObject(`ref/tags/${tag}`);
  while (object.type === 'tag') {
    object = getObject(`tags/${object.sha}`);
  }
  if (object.type !== 'commit' || object.sha !== commit) {
    throw new Error(`Tag ${tag} no longer points to the tested commit ${commit}.`);
  }
}

function viewRelease() {
  const result = spawnSync('gh', ['release', 'view', tag, '--json', 'isDraft,assets'], { encoding: 'utf8' });
  if (result.error) throw result.error;
  if (result.status === 0) return JSON.parse(result.stdout);
  if (result.status === 1 && /^(?:gh: )?release not found$/i.test(result.stderr.trim())) return null;
  throw new Error(result.stderr.trim() || `gh release view failed (${result.status ?? result.signal}).`);
}

function verifyAsset(archive, asset) {
  const directory = mkdtempSync(join(tmpdir(), 'questtidy-release-'));
  try {
    gh(['release', 'download', tag, '--pattern', asset, '--dir', directory]);
    if (!readFileSync(archive).equals(readFileSync(join(directory, asset)))) {
      throw new Error(`Existing release asset differs from the tested ZIP: ${asset}`);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

function publish(path) {
  const version = /^v((?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*))$/.exec(tag ?? '')?.[1];
  if (!repo || !version || !/^[a-f0-9]{40}$/.test(commit ?? '')) {
    throw new Error('Set GH_REPO, GITHUB_REF_NAME (vX.Y.Z), and BUILD_COMMIT (full Git SHA).');
  }

  const asset = `QuestTidy-${version}.zip`;
  if (!path || basename(path) !== asset) throw new Error(`Pass the tested ${asset} as the only argument.`);
  const archive = resolve(path);
  if (!statSync(archive, { throwIfNoEntry: false })?.isFile()) throw new Error(`ZIP not found: ${archive}`);

  verifyTag();
  const release = viewRelease();
  if (!release) {
    const url = gh([
      'release', 'create', tag, archive, '--verify-tag', '--title', `QuestTidy ${version}`,
      '--generate-notes', '--notes',
      'Download the QuestTidy ZIP under Assets. Extract the `QuestTidy` folder into World of Warcraft Forever’s `Interface/AddOns` directory.',
    ]);
    console.log(url);
    return;
  }

  if (release.assets.some(({ name }) => name === asset)) {
    verifyAsset(archive, asset);
  } else if (release.isDraft) {
    gh(['release', 'upload', tag, archive]);
  } else {
    throw new Error(`Published release ${tag} is missing ${asset}.`);
  }

  if (release.isDraft) {
    verifyTag();
    gh(['release', 'edit', tag, '--draft=false']);
  }
  console.log(`Release ${tag} has the tested ${asset}.`);
}

try {
  if (process.argv.length !== 3) throw new Error('Usage: node scripts/publish.mjs <release.zip>');
  publish(process.argv[2]);
} catch (error) {
  console.error(error.stderr?.trim() || error.message);
  process.exitCode = 1;
}
