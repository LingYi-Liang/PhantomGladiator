const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

module.exports = function createI18n() {
  const context = vm.createContext({ Intl });
  for (const file of ["i18n.js", "i18n-more.js"]) {
    vm.runInContext(fs.readFileSync(path.join(__dirname, "prototype", file), "utf8"), context, { filename: file });
  }
  return vm.runInContext("I18N", context);
};
