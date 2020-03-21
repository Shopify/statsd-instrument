#include <ruby.h>
#include <ruby/encoding.h>

#define MAX_DATAGRAM_SIZE 4096

static ID idTr, idNormalizeTags, idDefaultTags, idPrefix;
static VALUE strNormalizeChars, strNormalizeReplacement;

static VALUE
normalize_name(VALUE self, VALUE name) {
  char *name_start = NULL;
  char *name_end = NULL;
  Check_Type(name, T_STRING);

  name_start = RSTRING_PTR(name);
  name_end = RSTRING_END(name);

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

static VALUE
generate_generic_datagram(VALUE self, VALUE name, VALUE value, VALUE type, VALUE sample_rate, VALUE tags) {
  VALUE prefix, normalized_name, str_value, str_sample_rate, default_tags, tag;
  VALUE normalized_tags = Qnil;
  char datagram[MAX_DATAGRAM_SIZE];
  int empty_default_tags = 1, empty_tags = 1;
  int len = 0, tags_len = 0, i = 0;

  MEMZERO(&datagram, char, MAX_DATAGRAM_SIZE);

  prefix = rb_ivar_get(self, idPrefix);
  if (RSTRING_LEN(prefix) != 0) {
    memcpy(datagram, StringValuePtr(prefix), RSTRING_LEN(prefix));
    len += RSTRING_LEN(prefix);
  }

  normalized_name = normalize_name(self, name);
  memcpy(datagram + len, StringValuePtr(normalized_name), RSTRING_LEN(normalized_name));
  len += RSTRING_LEN(normalized_name);

  memcpy(datagram + len, ":", 1);
  len += 1;
  str_value = rb_obj_as_string(value);
  memcpy(datagram + len, StringValuePtr(str_value), RSTRING_LEN(str_value));
  len += RSTRING_LEN(str_value);

  memcpy(datagram + len, "|", 1);
  len += 1;
  memcpy(datagram + len, StringValuePtr(type), RSTRING_LEN(type));
  len += RSTRING_LEN(type);

  if (RTEST(sample_rate) && NUM2INT(sample_rate) < 1) {
    memcpy(datagram + len, "|@", 2);
    len += 2;
    str_sample_rate = rb_obj_as_string(sample_rate);
    memcpy(datagram + len, StringValuePtr(str_sample_rate), RSTRING_LEN(str_sample_rate));
    len += RSTRING_LEN(str_sample_rate);
  }

  default_tags = rb_ivar_get(self, idDefaultTags);

  empty_default_tags = (RTEST(default_tags) ? RARRAY_LEN(default_tags) == 0 : 0);
  if (RB_TYPE_P(tags, T_HASH) && !RHASH_EMPTY_P(tags)) {
    empty_tags = 0;
  } else if (RB_TYPE_P(tags, T_ARRAY) && RARRAY_LEN(tags) != 0) {
    empty_tags = 0;
  }

  if (empty_default_tags && !empty_tags) {
    normalized_tags = rb_funcall(self, idNormalizeTags, 1, tags);
  } else if (!empty_default_tags && !empty_tags) {
    normalized_tags = rb_ary_concat(rb_funcall(self, idNormalizeTags, 1, tags), default_tags);
  } else if (!empty_default_tags && empty_tags) {
    normalized_tags = default_tags;
  }

  if (RTEST(normalized_tags)) {
    memcpy(datagram + len, "|#", 2);
    len += 2;

    tags_len = RARRAY_LEN(normalized_tags);
    for (i = 0; i < tags_len; ++i) {
      tag = RARRAY_AREF(normalized_tags, i);
      memcpy(datagram + len, StringValuePtr(tag), RSTRING_LEN(tag));
      len += RSTRING_LEN(tag);
      if (i < tags_len - 1) {
        memcpy(datagram + len, ",", 1);
        len += 1;
      }
    }
  }

  return rb_str_new(datagram, len);
  RB_GC_GUARD(normalized_tags);
}

void Init_statsd()
{
  VALUE mStatsd, mInstrument, cDatagramBuilder;

  mStatsd = rb_define_module("StatsD");
  mInstrument = rb_define_module_under(mStatsd, "Instrument");
  cDatagramBuilder = rb_define_class_under(mInstrument, "DatagramBuilder", rb_cObject);

  idTr = rb_intern("tr");
  idNormalizeTags = rb_intern("normalize_tags");
  idDefaultTags = rb_intern("@default_tags");
  idPrefix = rb_intern("@prefix");
  strNormalizeChars = rb_str_new_cstr(":|@");
  rb_global_variable(&strNormalizeChars);
  strNormalizeReplacement = rb_str_new_cstr("_");
  rb_global_variable(&strNormalizeReplacement);

  rb_define_protected_method(cDatagramBuilder, "normalize_name", normalize_name, 1);
  rb_define_protected_method(cDatagramBuilder, "generate_generic_datagram", generate_generic_datagram, 5);
}
