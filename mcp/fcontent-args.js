export function buildFcontentArgs({ query, path, max_matches, case_insensitive }) {
  const args = ["-o", "json"];

  if (max_matches !== undefined) args.push("-m", String(max_matches));

  const rgArgs = ["-F"];
  if (case_insensitive) rgArgs.push("-i");
  args.push("--rg-args", rgArgs.join(" "));

  // Terminate option parsing so dash-prefixed literals stay literals.
  args.push("--", query);
  if (path) args.push(path);

  return args;
}
