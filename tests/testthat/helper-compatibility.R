# Production helpers use shinyOAuth's public methods. Tests also inspect S7
# properties; base @ supports those only since R 4.3. Use S7's backport in this
# test environment on older R, as recommended by its package compatibility guide.
if (getRversion() < "4.3.0") {
  `@` <- S7::`@`
}
