/**
 * simple_app.cpp - VMPacker 测试程序
 *
 * 包含常用指令的计算逻辑及日志打印，用于验证 VMP 保护后程序能否正常运行。
 * 核心函数 log2Console 将作为保护目标。
 *
 * 编译: 见 test/Makefile
 * 保护: go run ./cmd/vmpacker/ -func log2Console -v -debug -o /tmp/simple_app_protected simple_app
 * 运行: ./simple_app_protected
 */

#include <stdio.h>
#include <string.h>

/**
 * log2Console - 模拟日志输出到控制台的核心函数
 *
 * 使用常用指令: 算术(ADD/SUB/MUL)、逻辑(AND/OR/XOR)、
 * 比较与分支、循环、内存访问等。
 * 该函数将被 VMP 保护。
 * extern "C" 保证符号名为 log2Console，便于 vmpacker -func 匹配。
 */
extern "C" int log2Console(const char* tag, int level, int value) {
  if (tag == 0)
    return -1;

  /* 简单 hash: 对 tag 各字节做运算 */
  unsigned int hash = 0x811c9dc5;
  int len = 0;
  const char* p = tag;
  while (*p != 0 && len < 64) {
    hash = (hash * 31) ^ (unsigned char)(*p);
    len++;
    p++;
  }

  /* 算术运算: value * 7 + hash % 100 */
  int a = value * 7;
  int b = (int)(hash % 100);
  int result = a + b;

  /* 条件分支 */
  if (level > 0) {
    result += 10;
  } else {
    result -= 5;
  }

  /* 循环: 累加 0..4 */
  int sum = 0;
  for (int i = 0; i < 5; i++) {
    sum += i;
  }
  result += sum;

  /* 位运算 */
  result = (result & 0xFFF) | ((result >> 12) << 12);

  return result;
}

/**
 * computeAndLog - 计算并格式化日志字符串（供 main 调用）
 */
void computeAndLog(const char* msg, int x, int y) {
  int z = log2Console(msg, 1, x + y);
  printf("[LOG] %s: x=%d, y=%d => result=%d\n", msg, x, y, z);
}

int main(int argc, char* argv[]) {
  printf("=== VMPacker Simple App Test ===\n");

  /* 调用被保护的 log2Console */
  computeAndLog("init", 10, 20);
  computeAndLog("step1", 5, 15);
  computeAndLog("step2", 100, 200);

  int final = log2Console("done", 1, 42);
  printf("[LOG] Final result: %d\n", final);

  printf("=== Test completed successfully ===\n");
  return 0;
}
