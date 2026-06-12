#!/bin/sh
set -eu

meson_file="${1:-meson.build}"

if grep -q "if not meson.is_cross_build()" "$meson_file"; then
  exit 0
fi

perl -0pi -e '
  my $matched = s{\n(g_ir_compiler = find_program\('\''g-ir-compiler'\''\)\n.*?^gnome\.generate_vapi\([^\n]*\n.*?^\s*\)(?:\n|$))}{
    my $block = $1;
    $block .= "\n" unless $block =~ /\n\z/;
    $block =~ s/^/  /mg;
    "\nif not meson.is_cross_build()\n$block" . "endif\n";
  }sme;

  die "Could not find GIR/VAPI block in $ARGV\n" unless $matched;
' "$meson_file"
