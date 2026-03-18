// Extract code blob (section 6) and RO data (section 2) from a .polkavm file.
// Output format: [u32 LE ro_len][ro_data][code_blob]
// This is what CoreMini expects: RO data to poke at 0x10000, code blob for host_machine.
// Usage: node extract-code-blob.mjs input.polkavm output.pvm

import { readFileSync, writeFileSync } from 'fs';

const [infile, outfile] = process.argv.slice(2);
if (!infile || !outfile) {
  console.error('Usage: node extract-code-blob.mjs input.polkavm output.pvm');
  process.exit(1);
}

const data = readFileSync(infile);

if (data.toString('ascii', 0, 3) !== 'PVM' || data[3] !== 0) {
  console.error('Bad magic:', data.slice(0, 4).toString('hex'));
  process.exit(1);
}

// Header: PVM\0 (4) + version (1) + blob_len (u64 LE, 8) = 13 bytes
let pos = 13;

// PolkaVM prefix-coded varint
function readVarint() {
  const first = data[pos++];
  const leadingOnes = Math.clz32(~(first << 24) >>> 0);
  if (leadingOnes === 0) return first;
  if (leadingOnes === 1) return ((first & 0x3f) << 8) | data[pos++];
  if (leadingOnes === 2) { const a = data[pos++], b = data[pos++]; return ((first & 0x1f) << 16) | (b << 8) | a; }
  if (leadingOnes === 3) { const a = data[pos++], b = data[pos++], c = data[pos++]; return ((first & 0x0f) << 24) | (c << 16) | (b << 8) | a; }
  const val = data.readUInt32LE(pos); pos += 4; return val;
}

let roData = null;
let codeBlob = null;

while (pos < data.length) {
  const sectionType = data[pos++];
  if (sectionType === 0) break;
  const sectionLen = readVarint();
  const sectionData = data.slice(pos, pos + sectionLen);
  pos += sectionLen;

  if (sectionType === 2) {
    roData = sectionData;
    console.log(`  RO data: ${sectionData.length} bytes`);
  }
  if (sectionType === 6) {
    codeBlob = sectionData;
    console.log(`  Code blob: ${sectionData.length} bytes`);
  }
}

if (!codeBlob) {
  console.error('ERROR: section 6 (code) not found');
  process.exit(1);
}

// Write code blob (pure deblob format, no RO data — compatible with host_machine)
writeFileSync(outfile, codeBlob);
console.log(`  Total .pvm: ${codeBlob.length} bytes`);

// Write RO data as separate file if present
if (roData && roData.length > 0) {
  const roFile = outfile.replace(/\.pvm$/, '.ro');
  writeFileSync(roFile, roData);
  console.log(`  RO data: ${roFile} (${roData.length} bytes)`);
}
