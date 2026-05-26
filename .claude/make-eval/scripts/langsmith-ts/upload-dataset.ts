/**
 * Upload evals/dataset.jsonl to LangSmith as `<DATASET_NAME>`.
 *
 * Idempotent: if the dataset already exists it is deleted and recreated so the
 * name stays stable across runs. Prior experiments tied to the old dataset id
 * are unlinked — bump the dataset name (v1 → v2) if you need to keep them.
 *
 * Run: pnpm eval:upload
 *
 * --------------------------------------------------------------------------
 * Template wiring — adjust two lines for your project:
 *   - DATASET_NAME — short identifier with a version suffix
 *   - DATASET_PATH — usually evals/dataset.jsonl
 * --------------------------------------------------------------------------
 */
import 'dotenv/config';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { Client } from 'langsmith';

const DATASET_NAME = '<dataset-name>-v1';
const DATASET_PATH = resolve(process.cwd(), 'evals/dataset.jsonl');

// Derive the LangSmith web URL from the API endpoint env var so this works
// for self-hosted instances too. SaaS default: https://smith.langchain.com.
function langsmithWebBase(): string {
  const endpoint = process.env.LANGSMITH_ENDPOINT ?? 'https://api.smith.langchain.com';
  return endpoint.replace('://api.', '://').replace(/\/$/, '');
}

type Example = {
  inputs: Record<string, unknown>;
  outputs: Record<string, unknown>;
  metadata?: Record<string, unknown>;
};

function loadJsonl(path: string): Example[] {
  return readFileSync(path, 'utf8')
    .trim()
    .split('\n')
    .filter((line) => line.length > 0)
    .map((line, i) => {
      try {
        return JSON.parse(line) as Example;
      } catch (err) {
        throw new Error(`Invalid JSON on line ${i + 1}: ${(err as Error).message}`);
      }
    });
}

async function main() {
  if (!process.env.LANGSMITH_API_KEY) {
    throw new Error('LANGSMITH_API_KEY is missing — see .env.example');
  }

  const examples = loadJsonl(DATASET_PATH);
  console.log(`Loaded ${examples.length} examples from ${DATASET_PATH}`);

  const client = new Client();

  let existingId: string | undefined;
  try {
    const existing = await client.readDataset({ datasetName: DATASET_NAME });
    existingId = existing.id;
  } catch {
    // not found — fine
  }

  if (existingId) {
    console.log(`Deleting existing dataset "${DATASET_NAME}" (${existingId})`);
    await client.deleteDataset({ datasetId: existingId });
  }

  const dataset = await client.createDataset(DATASET_NAME, {
    description: '<one-line description of what this dataset tests>',
  });
  console.log(`Created dataset "${DATASET_NAME}" (${dataset.id})`);

  await client.createExamples({
    inputs: examples.map((e) => e.inputs),
    outputs: examples.map((e) => e.outputs),
    metadata: examples.map((e) => e.metadata ?? {}),
    datasetId: dataset.id,
  });
  console.log(`Uploaded ${examples.length} examples`);

  const datasetUrl = `${langsmithWebBase()}/o/-/datasets/${dataset.id}`;
  console.log('');
  console.log(`Dataset:     ${datasetUrl}`);
  console.log(`Experiments: ${datasetUrl}/compare`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
