RAGEL = ragel

.SUFFIXES: .rl

.rl.c:
	$(RAGEL) -G2 $<
	$(BASERUBY) -pli -e '$$_.sub!(/[ \t]+$$/, "")' \
	-e '$$_.sub!(/^static const int (JSON_.*=.*);$$/, "enum {\\1};")' \
	-e '$$header ||= $$_ = "/* This file is automatically generated from parser.rl by using ragel */" + $$_' $@

parser.c:
