import resolve from "rollup-plugin-node-resolve"
import commonjs from "rollup-plugin-commonjs"
import babel from "rollup-plugin-babel"

export default {
  input: "rails-ujs.js",
  output: {
    file: "compiled-rails-ujs.js",
    format: "umd",
    name: "Rails"
  },
  plugins: [
    resolve(),
    commonjs(),
    babel(),
  ]
}
