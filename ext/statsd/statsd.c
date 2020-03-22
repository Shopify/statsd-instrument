#include <ruby.h>
#include <ruby/encoding.h>

#define DATAGRAM_SIZE_MAX 4096
#define NORMALIZED_TAGS_CACHE_ENABLED 1
#define NORMALIZED_TAGS_CACHE_MAX 512
#define NORMALIZED_NAMES_CACHE_ENABLED 1
#define NORMALIZED_NAMES_CACHE_MAX 512

static ID idTr, idNormalizeTags, idDefaultTags, idPrefix, idNormalizedTagsCache, idNormalizedNamesCache;
static VALUE strNormalizeChars, strNormalizeReplacement;

static VALUE
initialize(int argc, VALUE *argv, VALUE self)
{
  rb_call_super(argc, argv);
  rb_ivar_set(self, idNormalizedTagsCache, rb_obj_hide(rb_hash_new()));
  rb_ivar_set(self, idNormalizedNamesCache, rb_obj_hide(rb_hash_new()));
  return self;
}

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

/* pure function not exposed to ruby with an intermediate bounded cache */
static VALUE
normalized_names_cached(VALUE self, VALUE name)
{
#ifdef NORMALIZED_NAMES_CACHE_ENABLED
  VALUE cached;
  VALUE cache = rb_ivar_get(self, idNormalizedNamesCache);
  cached = rb_hash_aref(cache, name);
  if (RTEST(cached)) {
    return cached;
  } else if (rb_hash_size_num(cache) < NORMALIZED_NAMES_CACHE_MAX) {
    cached = normalize_name(self, name);
    rb_hash_aset(cache, name, cached);
    return cached;
  }
  return normalize_name(self, name);
  RB_GC_GUARD(cached);
#else
  return normalize_name(self, name);
#endif
}

/* pure function not exposed to ruby with an intermediate bounded cache */
static VALUE
normalized_tags_cached(VALUE self, VALUE tags)
{
#ifdef NORMALIZED_TAGS_CACHE_ENABLED
  VALUE cached;
  VALUE cache = rb_ivar_get(self, idNormalizedTagsCache);
  cached = rb_hash_aref(cache, tags);
  if (RTEST(cached)) {
    return cached;
  } else if (rb_hash_size_num(cache) < NORMALIZED_TAGS_CACHE_MAX) {
    cached = rb_funcall(self, idNormalizeTags, 1, tags);
    rb_hash_aset(cache, tags, cached);
    return cached;
  }
  return rb_funcall(self, idNormalizeTags, 1, tags);
  RB_GC_GUARD(cached);
#else
  return rb_funcall(self, idNormalizeTags, 1, tags);
#endif
}

static VALUE
generate_generic_datagram(VALUE self, VALUE name, VALUE value, VALUE type, VALUE sample_rate, VALUE tags) {
  VALUE prefix, normalized_name, str_value, str_sample_rate, default_tags, tag;
  VALUE normalized_tags = Qnil;
  char datagram[DATAGRAM_SIZE_MAX];
  int empty_default_tags = 1, empty_tags = 1;
  int len = 0, tags_len = 0, i = 0;
  long chunk_len = 0;

  prefix = rb_ivar_get(self, idPrefix);
  if ((chunk_len = RSTRING_LEN(prefix)) != 0) {
    if (len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
    memcpy(datagram, StringValuePtr(prefix), chunk_len);
    len += chunk_len;
  }

  normalized_name = normalized_names_cached(self, name);
  chunk_len = RSTRING_LEN(normalized_name);
  if (len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
  memcpy(datagram + len, StringValuePtr(normalized_name), chunk_len);
  len += chunk_len;

  if (len + 1 > DATAGRAM_SIZE_MAX) goto finalize_datagram;
  memcpy(datagram + len, ":", 1);
  len += 1;
  str_value = rb_obj_as_string(value);
  chunk_len = RSTRING_LEN(str_value);
  if (len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
  memcpy(datagram + len, StringValuePtr(str_value), chunk_len);
  len += chunk_len;

  if (len + 1 > DATAGRAM_SIZE_MAX) goto finalize_datagram;
  memcpy(datagram + len, "|", 1);
  len += 1;
  chunk_len = RSTRING_LEN(type);
  if (len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
  memcpy(datagram + len, StringValuePtr(type), chunk_len);
  len += chunk_len;

  if (RTEST(sample_rate) && NUM2INT(sample_rate) < 1) {
    if (len + 2 > DATAGRAM_SIZE_MAX) goto finalize_datagram;
    memcpy(datagram + len, "|@", 2);
    len += 2;
    str_sample_rate = rb_obj_as_string(sample_rate);
    chunk_len = RSTRING_LEN(str_sample_rate);
    if (len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
    memcpy(datagram + len, StringValuePtr(str_sample_rate), chunk_len);
    len += chunk_len;
  }

  default_tags = rb_ivar_get(self, idDefaultTags);

  empty_default_tags = (RTEST(default_tags) ? RARRAY_LEN(default_tags) == 0 : 0);
  if (RB_TYPE_P(tags, T_HASH) && !RHASH_EMPTY_P(tags)) {
    empty_tags = 0;
  } else if (RB_TYPE_P(tags, T_ARRAY) && RARRAY_LEN(tags) != 0) {
    empty_tags = 0;
  }

  if (empty_default_tags && !empty_tags) {
    normalized_tags = normalized_tags_cached(self, tags);
  } else if (!empty_default_tags && !empty_tags) {
    normalized_tags = rb_ary_concat(normalized_tags_cached(self, tags), default_tags);
  } else if (!empty_default_tags && empty_tags) {
    normalized_tags = default_tags;
  }

  if (RTEST(normalized_tags)) {
    if (len + 2 > DATAGRAM_SIZE_MAX) goto finalize_datagram;
    memcpy(datagram + len, "|#", 2);
    len += 2;

    tags_len = RARRAY_LEN(normalized_tags);
    for (i = 0; i < tags_len; ++i) {
      tag = RARRAY_AREF(normalized_tags, i);
      chunk_len = RSTRING_LEN(tag);
      if (len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
      memcpy(datagram + len, StringValuePtr(tag), chunk_len);
      len += chunk_len;
      if (i < tags_len - 1) {
        if (len + 1 > DATAGRAM_SIZE_MAX) goto finalize_datagram;
        memcpy(datagram + len, ",", 1);
        len += 1;
      }
    }
  }

finalize_datagram:
  return rb_str_new(datagram, len);
  RB_GC_GUARD(normalized_tags);
}

void Init_statsd()
{
  VALUE mStatsd, mInstrument, cDatagramBuilder, mCDatagramBuilder;

  mStatsd = rb_define_module("StatsD");
  mInstrument = rb_define_module_under(mStatsd, "Instrument");
  cDatagramBuilder = rb_define_class_under(mInstrument, "DatagramBuilder", rb_cObject);
  mCDatagramBuilder = rb_define_module_under(mInstrument, "CDatagramBuilder");

  idTr = rb_intern("tr");
  idNormalizeTags = rb_intern("normalize_tags");
  idDefaultTags = rb_intern("@default_tags");
  idPrefix = rb_intern("@prefix");
  idNormalizedNamesCache = rb_intern("@__normalized_names_cache");
  idNormalizedTagsCache = rb_intern("@__normalized_tags_cache");
  strNormalizeChars = rb_str_new_cstr(":|@");
  rb_global_variable(&strNormalizeChars);
  strNormalizeReplacement = rb_str_new_cstr("_");
  rb_global_variable(&strNormalizeReplacement);

  rb_define_method(mCDatagramBuilder, "initialize", initialize, -1);
  rb_define_protected_method(mCDatagramBuilder, "normalize_name", normalize_name, 1);
  rb_define_protected_method(mCDatagramBuilder, "generate_generic_datagram", generate_generic_datagram, 5);

  rb_prepend_module(cDatagramBuilder, mCDatagramBuilder);
}
