import { chmodSync, cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { arch, platform } from 'node:process';
import { spawnSync } from 'node:child_process';

if (platform !== 'darwin') {
  console.error('macos:package must run on macOS.');
  process.exit(1);
}

const root = resolve(new URL('..', import.meta.url).pathname);
const releaseRoot = join(root, 'release');
const packageJson = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const version = process.env.STEMACLE_RELEASE_VERSION || packageJson.version;
const buildNumber = process.env.STEMACLE_BUILD_NUMBER || version.replace(/\D/g, '') || '1';
const appName = 'Stemacle';
const appBundle = join(releaseRoot, `${appName}.app`);
const contents = join(appBundle, 'Contents');
const macOSDir = join(contents, 'MacOS');
const resourcesDir = join(contents, 'Resources');
const binaryName = 'StemacleMac';
const appIconName = 'StemacleIcon.icns';
const binaryCandidates = [
  join(root, 'native/macos/.build/release/StemacleMac'),
  join(root, 'native/macos/.build/apple/Products/Release/StemacleMac'),
];
const binaryPath = binaryCandidates.find((candidate) => existsSync(candidate));

if (!binaryPath) {
  console.error('Missing release binary. Run `npm run macos:build` first.');
  process.exit(1);
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    cwd: root,
    stdio: 'inherit',
    ...options,
  });
  if (result.status !== 0) {
    process.exit(result.status || 1);
  }
}

function capture(command, args) {
  return spawnSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

function findDeveloperIdApplicationIdentity() {
  const result = capture('security', ['find-identity', '-v', '-p', 'codesigning']);
  if (result.status !== 0) {
    return '';
  }

  const match = result.stdout.match(/"([^"]*Developer ID Application: [^"]+)"/);
  return match?.[1] ?? '';
}

function signingLabel(identity) {
  return identity === '-' ? 'ad-hoc signature' : identity;
}

rmSync(appBundle, { recursive: true, force: true });
mkdirSync(macOSDir, { recursive: true });
mkdirSync(resourcesDir, { recursive: true });

cpSync(binaryPath, join(macOSDir, binaryName));
chmodSync(join(macOSDir, binaryName), 0o755);

cpSync(join(root, 'native', 'electron', 'icon.icns'), join(resourcesDir, appIconName));
cpSync(join(root, 'dist/native'), join(resourcesDir, 'repo/dist/native'), { recursive: true });
cpSync(join(root, 'assets'), join(resourcesDir, 'repo/assets'), { recursive: true });
cpSync(join(root, 'app'), join(resourcesDir, 'repo/app'), { recursive: true });
cpSync(join(root, 'apps'), join(resourcesDir, 'repo/apps'), { recursive: true });
cpSync(join(root, 'samples'), join(resourcesDir, 'repo/samples'), { recursive: true });

writeFileSync(join(contents, 'Info.plist'), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Stemacle</string>
  <key>CFBundleExecutable</key>
  <string>${binaryName}</string>
  <key>CFBundleIdentifier</key>
  <string>com.stemacle.mac</string>
  <key>CFBundleIconFile</key>
  <string>${appIconName}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Stemacle</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${version}</string>
  <key>CFBundleVersion</key>
  <string>${buildNumber}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.music</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
`);

const distribution = process.env.STEMACLE_MAC_DISTRIBUTION || 'github';
const identity = distribution === 'appstore'
  ? process.env.MAC_APP_STORE_IDENTITY
  : (process.env.STEMACLE_MAC_SIGNING_IDENTITY
      || process.env.MAC_DEVELOPER_ID
      || findDeveloperIdApplicationIdentity()
      || '-');
const appEntitlements = distribution === 'appstore'
  ? join(root, 'native/macos/StemacleMac.entitlements')
  : '';

if (distribution === 'appstore' && !identity) {
  console.error('Missing MAC_APP_STORE_IDENTITY for App Store signing.');
  process.exit(1);
}

console.log(`Signing ${appName}.app with ${signingLabel(identity)}.`);
const appSignArgs = [
  '--force',
  '--sign',
  identity,
];
if (appEntitlements) {
  appSignArgs.push('--entitlements', appEntitlements);
}
appSignArgs.push(
  '--options',
  'runtime',
  appBundle,
);
run('codesign', appSignArgs);

const outputArch = process.env.STEMACLE_MAC_ARCH || (arch === 'arm64' ? 'arm64' : 'x64');
const versionedBaseName = `Stemacle-${version}-${outputArch}`;
const zipPath = join(releaseRoot, `${versionedBaseName}-mac.zip`);
const dmgPath = join(releaseRoot, `${versionedBaseName}.dmg`);
const latestZipPath = join(releaseRoot, `Stemacle-mac-${outputArch}.zip`);
const latestDmgPath = join(releaseRoot, `Stemacle-mac-${outputArch}.dmg`);
for (const artifact of [zipPath, dmgPath, latestZipPath, latestDmgPath]) {
  rmSync(artifact, { force: true });
  rmSync(`${artifact}.blockmap`, { force: true });
}
run('ditto', ['-c', '-k', '--keepParent', appBundle, zipPath], { cwd: releaseRoot });
run('hdiutil', [
  'create',
  '-volname',
  appName,
  '-srcfolder',
  appBundle,
  '-ov',
  '-format',
  'UDZO',
  dmgPath,
]);
if (identity !== '-') {
  run('codesign', ['--force', '--sign', identity, dmgPath]);
} else {
  console.warn('Skipping DMG codesign because no Developer ID Application identity was found.');
}
cpSync(zipPath, latestZipPath);
cpSync(dmgPath, latestDmgPath);

if (distribution === 'appstore') {
  const installerIdentity = process.env.MAC_INSTALLER_IDENTITY;
  if (!installerIdentity) {
    console.error('Missing MAC_INSTALLER_IDENTITY for App Store packaging.');
    process.exit(1);
  }
  const pkgPath = join(releaseRoot, `Stemacle-mac-appstore-${outputArch}.pkg`);
  rmSync(pkgPath, { force: true });
  run('productbuild', [
    '--component',
    appBundle,
    '/Applications',
    '--sign',
    installerIdentity,
    pkgPath,
  ]);
}

console.log(`Packaged ${appBundle}`);
console.log(`Created ${zipPath}`);
console.log(`Created ${dmgPath}`);
