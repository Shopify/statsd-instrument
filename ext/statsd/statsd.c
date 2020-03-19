#include <ruby.h>
#include <ruby/encoding.h>

static VALUE idTr;
static VALUE strNormalizeChars, strNormalizeReplacement;

static VALUE
normalize_name(VALUE self, VALUE name) {
  Check_Type(name, T_STRING);

  char *name_start = RSTRING_PTR(name);
  char *name_end = RSTRING_END(name);

  while (name_start < name_end) {
    if (*name_start == ':' || *name_start == '|' || *name_start == '@') {
      break;
    }
    name_start++;
  }

  if (name_start == name_end) {
    return name;
  }
  return rb_funcall(name, idTr, 2, strNormalizeChars, strNormalizeReplacement);
}

void Init_statsd()
{
  VALUE mStatsd, mInstrument, cDatagramBuilder;

  mStatsd = rb_define_module("StatsD");
  mInstrument = rb_define_module_under(mStatsd, "Instrument");
  cDatagramBuilder = rb_define_class_under(mInstrument, "DatagramBuilder", rb_cObject);

  idTr = rb_intern("tr");
  strNormalizeChars = rb_str_new_cstr(":|@");
  strNormalizeReplacement = rb_str_new_cstr("_");

  rb_global_variable(&strNormalizeChars);
  rb_global_variable(&strNormalizeReplacement);

  rb_define_protected_method(cDatagramBuilder, "normalize_name", normalize_name, 1);
}
