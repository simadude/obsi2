const luamin = require('lua-format')
const fs = require("fs")

const source = fs.readFileSync(process.argv[2]).toString()
const minSource = luamin.Minify(source, {
  RenameVariables: true,
  RenameGlobals: false, // evil?
  SolveMath: false // if you have a number before `end` keyword, then it breaks.
})

fs.writeFile(process.argv[3], minSource, (err) => {
	if (err) {
	  console.error(err);
	  return;
	}
	console.log('Ok!');
});
