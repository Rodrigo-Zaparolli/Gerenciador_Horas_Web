// Bundled with scripts/build_comment_spelling.cjs. Runs entirely in a Worker.
import { loadModule } from '../build/comment-spell-build/node_modules/hunspell-asm/dist/cjs/index.js';
let checker;
const ready = (async () => {
  const factory = await loadModule({timeout:15000});
  const buffers = await Promise.all(['index.aff','index.dic'].map(async name => {
    const response = await fetch(new URL(name, self.location.href));
    if (!response.ok) throw new Error('dictionary unavailable');
    return new Uint8Array(await response.arrayBuffer());
  }));
  checker = factory.create(factory.mountBuffer(buffers[0]), factory.mountBuffer(buffers[1]));
  for (const word of ['E-Desk','Promob','Cyncly','Excel','Enterprise','Professional','Plugin','plugin','Checklist','checklist']) checker.addWord(word);
  self.postMessage({type:'ready'});
})();
ready.catch(() => self.postMessage({type:'unavailable'}));
self.onmessage = async ({data}) => {
  try {
    await ready;
    if (data.type === 'check') {
      const wrong = data.words.filter(word => word.length <= 64 && !checker.spell(word));
      self.postMessage({type:'checked',id:data.id,wrong});
    } else if (data.type === 'suggest') {
      self.postMessage({type:'suggestions',id:data.id,word:data.word,values:checker.suggest(data.word).slice(0,6)});
    }
  } catch (_) { self.postMessage({type:'unavailable'}); }
};
