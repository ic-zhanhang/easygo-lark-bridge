#!/usr/bin/env bash
# 未配置 VOLC_EMBEDDING_API_KEY 时跳过向量嵌入，仅 FTS 关键词搜索（避免启动刷屏报错）
set -euo pipefail

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAW_INSTALL_DIR="${CLAW_INSTALL_DIR:-${PACK_ROOT}/claw}"
SERVER="${CLAW_INSTALL_DIR}/server.ts"
MEMORY="${CLAW_INSTALL_DIR}/memory.ts"

if [[ ! -f "${SERVER}" ]]; then
  echo "跳过 patch-claw-memory-fts-only: 未找到 ${SERVER}"
  exit 0
fi

python3 - "${SERVER}" "${MEMORY}" <<'PY'
from pathlib import Path
import sys

server = Path(sys.argv[1])
memory_path = Path(sys.argv[2])
text = server.read_text()
marker = "CLAW_MEMORY_FTS_ONLY"

if marker in text:
    print("patch-claw-memory-fts-only: server 已应用，跳过")
else:
    old_init = """let memory: MemoryManager | undefined;
try {
\tmemory = new MemoryManager({
\t\tworkspaceDir: defaultWorkspace,
\t\tembeddingApiKey: config.VOLC_EMBEDDING_API_KEY,
\t\tembeddingModel: config.VOLC_EMBEDDING_MODEL,
\t\tembeddingEndpoint: "https://ark.cn-beijing.volces.com/api/v3/embeddings/multimodal",
\t});
\tsetTimeout(() => {
\t\tmemory!.index().then((n) => {
\t\t\tif (n > 0) console.log(`[记忆] 启动索引完成: ${n} 块`);
\t\t}).catch((e) => console.warn(`[记忆] 启动索引失败: ${e}`));
\t}, 3000);
} catch (e) {
\tconsole.warn(`[记忆] 初始化失败（功能降级）: ${e}`);
}"""

    new_init = """let memory: MemoryManager | undefined;
const embeddingEnabled = Boolean(config.VOLC_EMBEDDING_API_KEY?.trim()); // CLAW_MEMORY_FTS_ONLY
try {
\tmemory = new MemoryManager({
\t\tworkspaceDir: defaultWorkspace,
\t\tembeddingApiKey: config.VOLC_EMBEDDING_API_KEY,
\t\tembeddingModel: config.VOLC_EMBEDDING_MODEL,
\t\tembeddingEndpoint: "https://ark.cn-beijing.volces.com/api/v3/embeddings/multimodal",
\t});
\tif (!embeddingEnabled) {
\t\tconsole.log("[记忆] 未配置 VOLC_EMBEDDING_API_KEY，仅 FTS 关键词搜索（可在 config/easygo.env 填写密钥启用向量检索）");
\t}
\tsetTimeout(() => {
\t\tmemory!.index().then((n) => {
\t\t\tif (n > 0) console.log(`[记忆] 启动索引完成: ${n} 块${embeddingEnabled ? "" : "（FTS-only）"}`);
\t\t}).catch((e) => console.warn(`[记忆] 启动索引失败: ${e}`));
\t}, 3000);
} catch (e) {
\tconsole.warn(`[记忆] 初始化失败（功能降级）: ${e}`);
}"""

    if old_init not in text:
        print("patch-claw-memory-fts-only: 无法定位 server 记忆初始化", file=sys.stderr)
        sys.exit(1)
    text = text.replace(old_init, new_init, 1)

    old_mem_cmd = '\t\t\tawait replyCard(messageId, "记忆系统未初始化（缺少向量嵌入 API Key）。\\n\\n请在 `.env` 中设置 `VOLC_EMBEDDING_API_KEY`。", { title: "记忆不可用", color: "orange" });'
    new_mem_cmd = '\t\t\tawait replyCard(messageId, "记忆系统未初始化。\\n\\n请检查 Claw 日志。", { title: "记忆不可用", color: "orange" });'
    if old_mem_cmd in text:
        text = text.replace(old_mem_cmd, new_mem_cmd, 1)

    server.write_text(text)
    print("patch-claw-memory-fts-only: server 记忆初始化已更新")

if memory_path.exists() and "CLAW_MEMORY_FTS_ONLY" not in memory_path.read_text():
    mem = memory_path.read_text()
    old_loop = """\t\t\t// 嵌入（优先读缓存）
\t\t\tconst embeddings: Array<number[] | null> = [];
\t\t\tfor (const chunk of chunks) {
\t\t\t\tconst cached = this.getCachedEmbedding(chunk.hash);
\t\t\t\tif (cached) {
\t\t\t\t\tembeddings.push(cached);
\t\t\t\t\tcacheHits++;
\t\t\t\t} else {
\t\t\t\t\ttry {
\t\t\t\t\t\tconst emb = await this.embedOne(chunk.text);
\t\t\t\t\t\tembeddings.push(emb);
\t\t\t\t\t\tapiCalls++;
\t\t\t\t\t} catch (err) {
\t\t\t\t\t\tconsole.warn(`[记忆] 嵌入失败 ${chunk.id}: ${err instanceof Error ? err.message : err}`);
\t\t\t\t\t\tembeddings.push(null);
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}"""

    new_loop = """\t\t\t// 嵌入（优先读缓存）；无 API Key 时跳过向量，仅 FTS // CLAW_MEMORY_FTS_ONLY
\t\t\tconst skipEmbed = !this.config.embeddingApiKey?.trim();
\t\t\tconst embeddings: Array<number[] | null> = [];
\t\t\tfor (const chunk of chunks) {
\t\t\t\tif (skipEmbed) {
\t\t\t\t\tembeddings.push(null);
\t\t\t\t\tcontinue;
\t\t\t\t}
\t\t\t\tconst cached = this.getCachedEmbedding(chunk.hash);
\t\t\t\tif (cached) {
\t\t\t\t\tembeddings.push(cached);
\t\t\t\t\tcacheHits++;
\t\t\t\t} else {
\t\t\t\t\ttry {
\t\t\t\t\t\tconst emb = await this.embedOne(chunk.text);
\t\t\t\t\t\tembeddings.push(emb);
\t\t\t\t\t\tapiCalls++;
\t\t\t\t\t} catch (err) {
\t\t\t\t\t\tconsole.warn(`[记忆] 嵌入失败 ${chunk.id}: ${err instanceof Error ? err.message : err}`);
\t\t\t\t\t\tembeddings.push(null);
\t\t\t\t\t}
\t\t\t\t}
\t\t\t}"""

    if old_loop not in mem:
        print("patch-claw-memory-fts-only: 无法定位 memory.ts 嵌入循环", file=sys.stderr)
        sys.exit(1)
    mem = mem.replace(old_loop, new_loop, 1)
    memory_path.write_text(mem)
    print("patch-claw-memory-fts-only: memory.ts 已跳过无 key 时的嵌入")
elif memory_path.exists():
    print("patch-claw-memory-fts-only: memory.ts 已应用，跳过")
PY

chmod +x "${BASH_SOURCE[0]}"
