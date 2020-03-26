#include <ruby.h>
#include <ruby/encoding.h>
#include <ruby/st.h>

#define DATAGRAM_SIZE_MAX 4096
#define SAMPLE_RATE_SIZE_MAX 16
#define NORMALIZED_TAGS_CACHE_ENABLED 1
#define NORMALIZED_TAGS_CACHE_MAX 512
#define NORMALIZED_NAMES_CACHE_ENABLED 1
#define NORMALIZED_NAMES_CACHE_MAX 512

static ID idTr, idNormalizeTags, idDefaultTags, idPrefix;
static VALUE strNormalizeChars, strNormalizeReplacement;

struct datagram_builder {
#ifdef NORMALIZED_TAGS_CACHE_ENABLED
  st_table *normalized_tags_cache;
#endif
#ifdef NORMALIZED_NAMES_CACHE_ENABLED
  st_table *normalized_names_cache;
#endif
  // cached default tags ivar to skip a lookup
  VALUE default_tags;
  int prefix_len;
  int len;
  // last member to not glob up cache lines to access other struct members
  char datagram[DATAGRAM_SIZE_MAX];
};

// GC callback to mark the wrapper struct. Conditionally symbol tables if caching is enabled (values only)
// and the cached default tags as well.
void
datagram_builder_mark(void *ptr)
{
  const struct datagram_builder *builder = (struct datagram_builder *)ptr;
#ifdef NORMALIZED_TAGS_CACHE_ENABLED
  rb_mark_tbl(builder->normalized_tags_cache);
#endif
#ifdef NORMALIZED_NAMES_CACHE_ENABLED
  rb_mark_tbl(builder->normalized_names_cache);
#endif
  rb_gc_mark(builder->default_tags);
}

// GC callback to free the wrapper struct. Conditionally symbol tables if caching is enabled
// and the struct itself.
void
datagram_builder_free(void *ptr)
{
  struct datagram_builder *builder = (struct datagram_builder *)ptr;
  if (!builder) return;
#ifdef NORMALIZED_TAGS_CACHE_ENABLED
  st_free_table(builder->normalized_tags_cache);
#endif
#ifdef NORMALIZED_NAMES_CACHE_ENABLED
  st_free_table(builder->normalized_names_cache);
#endif
  xfree(builder);
}

// Be nice to ObjectSpace and let the size be known. We'd likely want some feedback on
// this with various normalized cache size values.
size_t
datagram_builder_size(const void *ptr)
{
  size_t size;
  const struct datagram_builder *builder = (struct datagram_builder *)ptr;
  size = sizeof(struct datagram_builder);
#ifdef NORMALIZED_TAGS_CACHE_ENABLED
  size += st_memsize(builder->normalized_tags_cache);
#endif
#ifdef NORMALIZED_NAMES_CACHE_ENABLED
  size += st_memsize(builder->normalized_names_cache);
#endif
  return size;
}

const rb_data_type_t datagram_builder_type = {
  .wrap_struct_name = "datagram_builder",
  .function = {
    .dmark = datagram_builder_mark,
    .dfree = datagram_builder_free,
    .dsize = datagram_builder_size,
  },
  .data = NULL,
  .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

#define get_datagram_builder_struct(self) \
  struct datagram_builder *builder = NULL; \
  TypedData_Get_Struct(self, struct datagram_builder, &datagram_builder_type, builder); \

static VALUE
datagram_builder_alloc(VALUE self)
{
  struct datagram_builder *builder = ZALLOC(struct datagram_builder);
#ifdef NORMALIZED_TAGS_CACHE_ENABLED
  builder->normalized_tags_cache = st_init_numtable_with_size(NORMALIZED_TAGS_CACHE_MAX);
#endif
#ifdef NORMALIZED_NAMES_CACHE_ENABLED
  builder->normalized_names_cache = st_init_numtable_with_size(NORMALIZED_NAMES_CACHE_MAX);
#endif
  return TypedData_Wrap_Struct(self, &datagram_builder_type, builder);
}

static VALUE
initialize(int argc, VALUE *argv, VALUE self)
{
  VALUE prefix;
  long chunk_len = 0;
  get_datagram_builder_struct(self);
  rb_call_super(argc, argv);

  // pre seed the buffer with the prefix and advance the offset as it's fixed for the lifetime of
  // the builder
  prefix = rb_ivar_get(self, idPrefix);
  if ((chunk_len = RSTRING_LEN(prefix)) != 0 && chunk_len < DATAGRAM_SIZE_MAX) {
    memcpy(builder->datagram, StringValuePtr(prefix), chunk_len);
    builder->prefix_len = (int)chunk_len;
  }

  // Cache the defaukt tags ivar on the lookup struct
  builder->default_tags = rb_ivar_get(self, idDefaultTags);
  return self;
}

inline static VALUE
normalize_name_fast_path(VALUE self, VALUE name)
{
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
  return Qnil;
}

static VALUE
normalize_name(VALUE self, VALUE name) {
  VALUE _name = normalize_name_fast_path(self, name);
  if (!NIL_P(_name)) return _name;
  return rb_funcall(name, idTr, 2, strNormalizeChars, strNormalizeReplacement);
}

/* pure function not exposed to ruby with an intermediate bounded cache */
static VALUE
normalized_names_cached(struct datagram_builder *builder, VALUE self, VALUE name)
{
#ifdef NORMALIZED_NAMES_CACHE_ENABLED
  st_index_t key;
  st_data_t val;
  VALUE cached;
  Check_Type(name, T_STRING);
  // Can hash on string contents directly as type has already been checked
  key = rb_str_hash(name);
  if (st_lookup(builder->normalized_names_cache, key, &val)){
    return (VALUE)val;
  } else if (builder->normalized_names_cache->num_entries < NORMALIZED_NAMES_CACHE_MAX) {
    cached = normalize_name(self, name);
    st_insert(builder->normalized_names_cache, key, (st_data_t)cached);
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
normalized_tags_cached(struct datagram_builder *builder, VALUE self, VALUE tags)
{
#ifdef NORMALIZED_TAGS_CACHE_ENABLED
  st_index_t key;
  st_data_t val;
  VALUE cached;
  // More involved hashing as we need to hash on the content of the container too
  // XXX: revisit
  key = (st_index_t)(FIX2LONG(rb_hash(tags)));
  if (st_lookup(builder->normalized_tags_cache, key, &val)){
    return (VALUE)val;
  } else if (builder->normalized_tags_cache->num_entries < NORMALIZED_TAGS_CACHE_MAX) {
    cached = rb_funcall(self, idNormalizeTags, 1, tags);
    st_insert(builder->normalized_tags_cache, key, (st_data_t)cached);
    return cached;
  }
  return rb_funcall(self, idNormalizeTags, 1, tags);
  RB_GC_GUARD(cached);
#else
  return rb_funcall(self, idNormalizeTags, 1, tags);
#endif
}

inline static int append_normalized_tags(struct datagram_builder *builder, VALUE normalized_tags, int trim_trailing_comma)
{
  VALUE tag;
  int tags_len = 0, chunk_len = 0, i = 0;
  tags_len = (int)RARRAY_LEN(normalized_tags);
  for (i = 0; i < tags_len; ++i) {
    tag = RARRAY_AREF(normalized_tags, i);
    chunk_len = (int)RSTRING_LEN(tag);
    if (builder->len + chunk_len > DATAGRAM_SIZE_MAX) return 0;
    memcpy(builder->datagram + builder->len, StringValuePtr(tag), chunk_len);
    builder->len += chunk_len;
    if (!trim_trailing_comma || i < tags_len - 1) {
      if (builder->len + 1 > DATAGRAM_SIZE_MAX) return 0;
      memcpy(builder->datagram + builder->len, ",", 1);
      builder->len += 1;
    }
  }
  return 1;
}

static VALUE
generate_generic_datagram(VALUE self, VALUE name, VALUE value, VALUE type, VALUE sample_rate, VALUE tags) {
  VALUE normalized_name, str_value, str_sample_rate;
  VALUE normalized_tags = Qnil;
  char sr_buf[SAMPLE_RATE_SIZE_MAX];
  int empty_default_tags = 1, empty_tags = 1;
  long chunk_len = 0;
  get_datagram_builder_struct(self);

  builder->len = builder->prefix_len;

  if (NIL_P(normalized_name = normalize_name_fast_path(self, name))) {
    normalized_name = normalized_names_cached(builder, self, name);
  }

  chunk_len = RSTRING_LEN(normalized_name);
  if (builder->len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
  memcpy(builder->datagram + builder->len, StringValuePtr(normalized_name), chunk_len);
  builder->len += chunk_len;

  if (builder->len + 1 > DATAGRAM_SIZE_MAX) goto finalize_datagram;
  memcpy(builder->datagram + builder->len, ":", 1);
  builder->len += 1;
  str_value = rb_obj_as_string(value);
  chunk_len = RSTRING_LEN(str_value);
  if (builder->len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
  memcpy(builder->datagram + builder->len, StringValuePtr(str_value), chunk_len);
  builder->len += chunk_len;

  if (builder->len + 1 > DATAGRAM_SIZE_MAX) goto finalize_datagram;
  memcpy(builder->datagram + builder->len, "|", 1);
  builder->len += 1;
  chunk_len = RSTRING_LEN(type);
  if (builder->len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
  memcpy(builder->datagram + builder->len, StringValuePtr(type), chunk_len);
  builder->len += chunk_len;

  if (RTEST(sample_rate) && NUM2INT(sample_rate) < 1) {
    if (builder->len + 2 > DATAGRAM_SIZE_MAX) goto finalize_datagram;
    memcpy(builder->datagram + builder->len, "|@", 2);
    builder->len += 2;
    if (RB_FIXNUM_P(sample_rate)) {
      chunk_len = snprintf(sr_buf, SAMPLE_RATE_SIZE_MAX, "%d", FIX2INT(sample_rate));
      if (builder->len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
      memcpy(builder->datagram + builder->len, sr_buf, chunk_len);
      builder->len += chunk_len;
    } else if (RB_FLOAT_TYPE_P(sample_rate)) {
      chunk_len = snprintf(sr_buf, SAMPLE_RATE_SIZE_MAX, "%g", RFLOAT_VALUE(sample_rate));
      if (builder->len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
      memcpy(builder->datagram + builder->len, sr_buf, chunk_len);
      builder->len += chunk_len;
    } else {
      str_sample_rate = rb_obj_as_string(sample_rate);
      chunk_len = RSTRING_LEN(str_sample_rate);
      if (builder->len + chunk_len > DATAGRAM_SIZE_MAX) goto finalize_datagram;
      memcpy(builder->datagram + builder->len, StringValuePtr(str_sample_rate), chunk_len);
      builder->len += chunk_len;
    }
  }

  empty_default_tags = (RTEST(builder->default_tags) ? RARRAY_LEN(builder->default_tags) == 0 : 0);
  if ((RB_TYPE_P(tags, T_HASH) && !RHASH_EMPTY_P(tags)) || (RB_TYPE_P(tags, T_ARRAY) && RARRAY_LEN(tags) != 0)) {
    empty_tags = 0;
  }
  if (!(empty_default_tags && empty_tags)) {
    if (builder->len + 2 > DATAGRAM_SIZE_MAX) goto finalize_datagram;
    memcpy(builder->datagram + builder->len, "|#", 2);
    builder->len += 2;
  }
  if (empty_default_tags && !empty_tags) {
    if (!append_normalized_tags(builder, normalized_tags_cached(builder, self, tags), 1)) goto finalize_datagram;
  } else if (!empty_default_tags && !empty_tags) {
    if (!append_normalized_tags(builder, normalized_tags_cached(builder, self, tags), 0)) goto finalize_datagram;
    if (!append_normalized_tags(builder, builder->default_tags, 1)) goto finalize_datagram;
  } else if (!empty_default_tags && empty_tags) {
    if (!append_normalized_tags(builder, builder->default_tags, 1)) goto finalize_datagram;
  }

finalize_datagram:
  return rb_str_new(builder->datagram, builder->len);
  RB_GC_GUARD(normalized_tags);
}

void Init_statsd()
{
  VALUE mStatsd, mInstrument, cDatagramBuilder, mCDatagramBuilder;

  mStatsd = rb_define_module("StatsD");
  mInstrument = rb_define_module_under(mStatsd, "Instrument");
  cDatagramBuilder = rb_define_class_under(mInstrument, "DatagramBuilder", rb_cObject);

  rb_define_alloc_func(cDatagramBuilder, datagram_builder_alloc);

  mCDatagramBuilder = rb_define_module_under(mInstrument, "CDatagramBuilder");

  idTr = rb_intern("tr");
  idNormalizeTags = rb_intern("normalize_tags");
  idDefaultTags = rb_intern("@default_tags");
  idPrefix = rb_intern("@prefix");
  strNormalizeChars = rb_str_new_cstr(":|@");
  rb_global_variable(&strNormalizeChars);
  strNormalizeReplacement = rb_str_new_cstr("_");
  rb_global_variable(&strNormalizeReplacement);

  rb_define_method(mCDatagramBuilder, "initialize", initialize, -1);
  rb_define_protected_method(mCDatagramBuilder, "normalize_name", normalize_name, 1);
  rb_define_protected_method(mCDatagramBuilder, "generate_generic_datagram", generate_generic_datagram, 5);

  rb_prepend_module(cDatagramBuilder, mCDatagramBuilder);
}
