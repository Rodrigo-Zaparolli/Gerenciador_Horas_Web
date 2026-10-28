// Build dependencies are isolated under build/comment-spell-build.
// npm install --prefix build/comment-spell-build --ignore-scripts --no-audit --no-fund hunspell-asm@4.0.2 dictionary-pt@4.0.0 esbuild@0.28.2
const esbuild=require('../build/comment-spell-build/node_modules/esbuild');
esbuild.buildSync({entryPoints:['scripts/comment_spelling_worker.js'],bundle:true,
 platform:'browser',mainFields:['browser','main'],format:'iife',target:'chrome120',minify:true,legalComments:'eof',
 outfile:'web/vendor/comment-spelling/worker.js'});

const fs=require('fs'),path=require('path');
const base='build/comment-spell-build/node_modules',dest='web/vendor/comment-spelling';
for(const name of ['index.aff','index.dic'])fs.copyFileSync(path.join(base,'dictionary-pt',name),path.join(dest,name));
fs.copyFileSync(path.join(base,'dictionary-pt','license'),path.join(dest,'dictionary-LICENSE.txt'));
for(const name of ['hunspell-asm','emscripten-wasm-loader','nanoid']){
 const license=fs.readdirSync(path.join(base,name)).find(file=>/^license/i.test(file));
 if(license)fs.copyFileSync(path.join(base,name,license),path.join(dest,name+'-LICENSE.txt'));
}
