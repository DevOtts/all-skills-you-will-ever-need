/**
 * Run the classifier under test against the LangSmith dataset.
 *
 * Exits non-zero if:
 *   - overall exact_match accuracy is below ACCURACY_THRESHOLD, OR
 *   - ANY case tagged metadata.category startsWith "DANGEROUS_" misses
 *     exact_match — the dangerous cell is a hard gate.
 *
 * Run: pnpm eval
 *
 * --------------------------------------------------------------------------
 * Template wiring — replace the marked sections for your project:
 *   1. Import the classifier you want to evaluate
 *   2. Define the target() function that takes one example's inputs and
 *      returns the run outputs
 *   3. Adjust evaluators (the exactMatch one fits most closed-label problems
 *      as-is; the second one is a domain-specific softer signal — replace or
 *      remove)
 *   4. Set DATASET_NAME to match upload-dataset.ts
 * --------------------------------------------------------------------------
 */
import 'dotenv/config';
import { evaluate } from 'langsmith/evaluation';
import { Client } from 'langsmith';

// 1. Import your classifier ------------------------------------------------
// import { MyClassifier } from '../src/path/to/classifier';

const DATASET_NAME = '<dataset-name>-v1';
const ACCURACY_THRESHOLD = 0.85;

// Derive the LangSmith web URL from the API endpoint env var so this works
// for self-hosted instances too. SaaS default: https://smith.langchain.com.
function langsmithWebBase(): string {
  const endpoint = process.env.LANGSMITH_ENDPOINT ?? 'https://api.smith.langchain.com';
  return endpoint.replace('://api.', '://').replace(/\/$/, '');
}

// 2. Wire the target function ----------------------------------------------
// The target receives one example's inputs and returns the run outputs.
// Catch errors so a single LLM failure doesn't tank the whole experiment.
const target = async (inputs: Record<string, unknown>) => {
  try {
    // const result = await classifier.run(inputs);
    // return { label: result };
    throw new Error('TODO: wire your classifier here');
  } catch (err) {
    return { label: null, error: (err as Error).message };
  }
};

// 3. Evaluators ------------------------------------------------------------
// Modern object-form signature (langsmith >= 0.2.x). The legacy
// (run, example) form is deprecated.
const exactMatch = ({
  outputs,
  referenceOutputs,
}: {
  outputs: Record<string, unknown>;
  referenceOutputs?: Record<string, unknown>;
}) => ({
  key: 'exact_match',
  // Replace 'label' below with whatever key your target() returns and your
  // dataset's outputs.* uses as the reference.
  score: outputs?.label === referenceOutputs?.label ? 1 : 0,
});

// Example of a second, softer evaluator — keep, adapt, or delete.
// Use when the dataset carries `metadata.expected_*` that the picked output
// can be checked against (e.g. "right family/category, even if not exact id").
//
// const softerSignal = ({
//   inputs,
//   outputs,
//   example,
// }: {
//   inputs: Record<string, unknown>;
//   outputs: Record<string, unknown>;
//   example: { metadata?: Record<string, unknown> };
// }) => ({
//   key: 'softer_signal',
//   score: 0, // implement
// });

async function main() {
  if (!process.env.LANGSMITH_API_KEY) {
    throw new Error('LANGSMITH_API_KEY is missing — see .env.example');
  }

  const model = process.env.OPENROUTER_MODEL ?? process.env.MODEL ?? 'default';
  const prefix = `classifier-${model.replace(/[^a-z0-9]/gi, '-')}`;

  console.log(`Running eval on dataset "${DATASET_NAME}" with model "${model}"`);

  const results = await evaluate(target, {
    data: DATASET_NAME,
    evaluators: [exactMatch /*, softerSignal */],
    experimentPrefix: prefix,
    maxConcurrency: 4,
  });

  // langsmith 0.2.x SDK quirk: `for await (const res of results)` yields ZERO
  // items because the ExperimentResults iterator's `next()` checks
  // `processedCount < results.length`, and the SDK's `processData()` already
  // bumped processedCount to the end while filling the array (it conflates
  // "pushed" with "iterated" into one counter). The `.results` array IS
  // populated by the time `await evaluate(...)` resolves — read it directly
  // with a plain `for ... of`, never `for await ... of`. If you get a green
  // experiment in the LangSmith UI but `0/0` in the terminal summary, this
  // is why.
  const pairs: Array<{ expected: unknown; picked: unknown }> = [];
  const dangerousMisses: string[] = [];
  const rows = (results as unknown as { results: Array<{ run: { outputs?: Record<string, unknown> }; example: { outputs?: Record<string, unknown>; metadata?: Record<string, unknown> } }> }).results;
  for (const res of rows) {
    const example = res.example as {
      outputs?: Record<string, unknown>;
      metadata?: Record<string, unknown>;
    };
    const run = res.run;
    // Adjust the comparison key to whatever your target() returns.
    const picked = run.outputs?.label;
    const expected = example.outputs?.label;
    pairs.push({ expected, picked });
    const isExact = picked === expected;
    const category = (example.metadata?.category as string | undefined) ?? '';
    if (!isExact && category.startsWith('DANGEROUS_')) {
      dangerousMisses.push(
        `  - ${category}: picked=${picked} expected=${expected}`,
      );
    }
  }

  // Confusion matrix — the LangSmith UI shows per-row scores but the
  // off-diagonal cell pattern is what the engineer reads to locate failure.
  // Keep this printout so `pnpm eval` is useful without leaving the terminal.
  const labels = Array.from(
    new Set(pairs.flatMap((p) => [String(p.expected ?? '∅'), String(p.picked ?? '∅')])),
  ).sort();
  const labelWidth = Math.max(...labels.map((l) => l.length), 8);
  const cellWidth = Math.max(4, labelWidth);
  const counts: Record<string, Record<string, number>> = {};
  for (const e of labels) counts[e] = Object.fromEntries(labels.map((l) => [l, 0]));
  for (const { expected, picked } of pairs) {
    const e = String(expected ?? '∅');
    const p = String(picked ?? '∅');
    counts[e] ??= Object.fromEntries(labels.map((l) => [l, 0]));
    counts[e][p] = (counts[e][p] ?? 0) + 1;
  }
  const total = pairs.length;
  const exact = pairs.filter((p) => p.expected === p.picked).length;
  const accuracy = total === 0 ? 0 : exact / total;
  console.log(`\nResults: ${exact}/${total} exact (${(accuracy * 100).toFixed(1)}%)`);
  console.log('\nConfusion matrix (rows = expected, cols = picked):');
  const pad = (s: string, n: number) => (s.length >= n ? s : s + ' '.repeat(n - s.length));
  const header = pad('', labelWidth) + ' | ' + labels.map((l) => pad(l, cellWidth)).join(' ');
  console.log(header);
  console.log('-'.repeat(header.length));
  for (const e of labels) {
    console.log(
      pad(e, labelWidth) +
        ' | ' +
        labels.map((p) => pad(String(counts[e][p] ?? 0), cellWidth)).join(' '),
    );
  }
  if (dangerousMisses.length > 0) {
    console.log(`\nDANGEROUS cell misses (${dangerousMisses.length}):`);
    console.log(dangerousMisses.join('\n'));
  }

  // Safe to read experimentName now — iteration is done.
  const webBase = langsmithWebBase();
  const client = new Client();
  let experimentUrl = '';
  try {
    const experimentName = (results as { experimentName?: string }).experimentName ?? prefix;
    const [dataset, project] = await Promise.all([
      client.readDataset({ datasetName: DATASET_NAME }),
      client.readProject({ projectName: experimentName }),
    ]);
    experimentUrl = `${webBase}/o/-/datasets/${dataset.id}/compare?selectedSessions=${project.id}`;
  } catch {
    experimentUrl = `${webBase}/o/-/datasets`;
  }
  console.log(`\nExperiment: ${experimentUrl}`);

  const accuracyPass = accuracy >= ACCURACY_THRESHOLD;
  const dangerousPass = dangerousMisses.length === 0;
  if (!accuracyPass) {
    console.error(
      `FAIL: accuracy ${(accuracy * 100).toFixed(1)}% < ${(ACCURACY_THRESHOLD * 100).toFixed(0)}% threshold`,
    );
  }
  if (!dangerousPass) {
    console.error(`FAIL: ${dangerousMisses.length} DANGEROUS case(s) missed — hard gate`);
  }
  if (!accuracyPass || !dangerousPass) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
