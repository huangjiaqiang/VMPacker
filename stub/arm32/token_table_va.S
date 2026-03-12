/* token_table_va.S — _token_table_va + get_self_va in .text.entry
 * ADR requires same-file symbol; packer patches _token_table_va at runtime. */
.section .text.entry, "ax", %progbits
.thumb
.syntax unified

/* Returns runtime address of _token_table_va (for PIE). */
.global get_self_va
.thumb_func
get_self_va:
  adr r0, _token_table_va
  bx lr

.align 2
.global _token_table_va
_token_table_va:
  .word 0

.section .note.GNU-stack, "", %progbits
