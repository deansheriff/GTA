// Lists Poly Pizza search results with licence and creator (D-024), so only CC0 / CC-BY models
// are picked:  node tools/art/polypizza_search.mjs speedboat yacht ...
for (const q of process.argv.slice(2)) {
  const html = await (await fetch(`https://poly.pizza/search/${encodeURIComponent(q)}`)).text();
  const m = html.match(/window\.__SERVER_APP_STATE__ =\s*(\{.*?\})<\/script>/s);
  if (!m) { console.log(`== ${q}: no data`); continue; }
  const data = JSON.parse(m[1]);
  const res = data.initialData?.result ?? [];
  console.log(`== ${q}`);
  for (const r of res.slice(0, 14)) console.log(`  ${r.publicID.padEnd(14)} ${r.licence.padEnd(11)} ${r.creator.username.padEnd(18)} ${r.title}`);
}
