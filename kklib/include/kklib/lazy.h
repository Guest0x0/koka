#pragma once
#ifndef KK_LAZY_H
#define KK_LAZY_H
/*---------------------------------------------------------------------------
  Copyright 2024, Microsoft Research, Daan Leijen, Anton Lorenzen

  This is free software; you can redistribute it and/or modify it under the
  terms of the Apache License, Version 2.0. A copy of the License can be
  found in the LICENSE file at the root of this distribution.
---------------------------------------------------------------------------*/

kk_decl_export bool kk_lazy_atomic_enter(kk_datatype_t lazy, int32_t indirect_tag, kk_context_t* ctx);
kk_decl_export void kk_lazy_atomic_unblock(kk_datatype_t lazy, kk_context_t* ctx);

static inline bool kk_datatype_is_whnf( kk_datatype_t lazy, int32_t indirect_tag, kk_context_t* ctx ) {
  return (kk_datatype_is_singleton(lazy) || kk_datatype_ptr_tag(lazy,ctx) < indirect_tag);
}

static inline bool kk_datatype_ptr_is_whnf( kk_datatype_t lazy, int32_t indirect_tag, kk_context_t* ctx ) {
  kk_assert(kk_datatype_is_ptr(lazy));
  return (kk_datatype_ptr_tag(lazy,ctx) < indirect_tag);
}

static inline bool kk_datatype_ptr_is_thread_shared( kk_datatype_ptr_t lazy, kk_context_t* ctx ) {
  kk_assert(kk_datatype_is_ptr(lazy));
  return kk_block_is_thread_shared(kk_datatype_as_ptr(lazy,ctx));
}


#endif // KK_LAZY_H
