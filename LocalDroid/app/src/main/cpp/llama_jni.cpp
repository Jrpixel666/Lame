// JNI bridge between Kotlin and llama.cpp.
// One model + context per handle; generation streams pieces through a callback.
#include <jni.h>
#include <android/log.h>
#include <atomic>
#include <string>
#include <vector>
#include "llama.h"

#define TAG "LocalDroidLLM"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

struct Session {
    llama_model*   model = nullptr;
    llama_context* ctx   = nullptr;
    llama_sampler* smpl  = nullptr;
    std::atomic<bool> stop{false};
};

// NewStringUTF expects modified UTF-8 and mangles emoji, so text crosses as bytes.
static jbyteArray jbytes(JNIEnv* env, const std::string& s) {
    jbyteArray a = env->NewByteArray(s.size());
    env->SetByteArrayRegion(a, 0, s.size(), reinterpret_cast<const jbyte*>(s.data()));
    return a;
}

static std::string jstr(JNIEnv* env, jstring s) {
    const char* c = env->GetStringUTFChars(s, nullptr);
    std::string out(c);
    env->ReleaseStringUTFChars(s, c);
    return out;
}

// Holds bytes until they form complete UTF-8, so Java never gets a split code point.
static size_t utf8_complete_len(const std::string& s) {
    size_t n = s.size(), i = n;
    int back = 0;
    while (i > 0 && back < 4) {
        unsigned char c = s[i - 1];
        if ((c & 0xC0) != 0x80) {
            int need = (c & 0x80) == 0 ? 1 : (c & 0xE0) == 0xC0 ? 2 : (c & 0xF0) == 0xE0 ? 3 : 4;
            return (back + 1 >= need) ? n : i - 1;
        }
        --i; ++back;
    }
    return n;
}

extern "C" JNIEXPORT void JNICALL
Java_com_localdroid_llm_LlamaNative_backendInit(JNIEnv*, jobject) {
    llama_backend_init();
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_localdroid_llm_LlamaNative_load(JNIEnv* env, jobject, jstring path,
                                         jint nCtx, jint nThreads, jfloat temp) {
    auto* s = new Session();
    llama_model_params mp = llama_model_default_params();
    mp.use_mmap = true;
    s->model = llama_model_load_from_file(jstr(env, path).c_str(), mp);
    if (!s->model) { LOGE("model load failed"); delete s; return 0; }

    llama_context_params cp = llama_context_default_params();
    cp.n_ctx = nCtx;
    cp.n_batch = 512;
    cp.n_threads = nThreads;
    cp.n_threads_batch = nThreads;
    s->ctx = llama_init_from_model(s->model, cp);
    if (!s->ctx) { llama_model_free(s->model); delete s; return 0; }

    s->smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(s->smpl, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(s->smpl, llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(s->smpl, llama_sampler_init_temp(temp));
    llama_sampler_chain_add(s->smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    LOGI("model loaded, ctx=%d threads=%d", nCtx, nThreads);
    return reinterpret_cast<jlong>(s);
}

// Applies the model's own chat template (stored in the GGUF) to role/content pairs.
extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_localdroid_llm_LlamaNative_applyTemplate(JNIEnv* env, jobject, jlong h,
                                                  jobjectArray roles, jobjectArray contents) {
    auto* s = reinterpret_cast<Session*>(h);
    jsize n = env->GetArrayLength(roles);
    std::vector<std::string> r(n), c(n);
    std::vector<llama_chat_message> msgs(n);
    for (jsize i = 0; i < n; ++i) {
        r[i] = jstr(env, (jstring) env->GetObjectArrayElement(roles, i));
        c[i] = jstr(env, (jstring) env->GetObjectArrayElement(contents, i));
        msgs[i] = { r[i].c_str(), c[i].c_str() };
    }
    const char* tmpl = llama_model_chat_template(s->model, nullptr);
    std::vector<char> buf(16384);
    int len = llama_chat_apply_template(tmpl, msgs.data(), n, true, buf.data(), buf.size());
    if (len > (int) buf.size()) {
        buf.resize(len);
        len = llama_chat_apply_template(tmpl, msgs.data(), n, true, buf.data(), buf.size());
    }
    if (len < 0) {  // No usable template: fall back to ChatML.
        std::string out;
        for (jsize i = 0; i < n; ++i) out += "<|im_start|>" + r[i] + "\n" + c[i] + "<|im_end|>\n";
        out += "<|im_start|>assistant\n";
        return jbytes(env, out);
    }
    return jbytes(env, std::string(buf.data(), len));
}

extern "C" JNIEXPORT jint JNICALL
Java_com_localdroid_llm_LlamaNative_generate(JNIEnv* env, jobject, jlong h,
                                             jbyteArray jprompt, jint maxTokens, jobject cb) {
    auto* s = reinterpret_cast<Session*>(h);
    s->stop = false;
    const llama_vocab* vocab = llama_model_get_vocab(s->model);
    jmethodID onToken = env->GetMethodID(env->GetObjectClass(cb), "onToken", "([B)V");

    // Fresh conversation each call: the Kotlin side resends the full history.
    llama_kv_cache_clear(s->ctx);

    jsize plen = env->GetArrayLength(jprompt);
    std::string prompt(plen, '\0');
    env->GetByteArrayRegion(jprompt, 0, plen, reinterpret_cast<jbyte*>(&prompt[0]));
    int n = -llama_tokenize(vocab, prompt.c_str(), prompt.size(), nullptr, 0, true, true);
    std::vector<llama_token> toks(n);
    llama_tokenize(vocab, prompt.c_str(), prompt.size(), toks.data(), n, true, true);

    int nCtx = llama_n_ctx(s->ctx);
    if ((int) toks.size() >= nCtx - 16) {  // Keep the tail if the history overflows.
        toks.erase(toks.begin(), toks.end() - (nCtx / 2));
    }

    // Feed the prompt in n_batch chunks.
    for (size_t i = 0; i < toks.size(); i += 512) {
        int cnt = std::min<size_t>(512, toks.size() - i);
        if (llama_decode(s->ctx, llama_batch_get_one(toks.data() + i, cnt)) != 0) {
            LOGE("prompt decode failed"); return -1;
        }
    }

    std::string pending;
    int produced = 0;
    int pos = toks.size();
    while (produced < maxTokens && !s->stop && pos < nCtx) {
        llama_token t = llama_sampler_sample(s->smpl, s->ctx, -1);
        if (llama_vocab_is_eog(vocab, t)) break;

        char piece[256];
        int len = llama_token_to_piece(vocab, t, piece, sizeof(piece), 0, false);
        if (len > 0) {
            pending.append(piece, len);
            size_t ok = utf8_complete_len(pending);
            if (ok > 0) {
                jbyteArray js = jbytes(env, pending.substr(0, ok));
                env->CallVoidMethod(cb, onToken, js);
                env->DeleteLocalRef(js);
                pending.erase(0, ok);
            }
        }
        if (llama_decode(s->ctx, llama_batch_get_one(&t, 1)) != 0) break;
        ++produced; ++pos;
    }
    return produced;
}

extern "C" JNIEXPORT void JNICALL
Java_com_localdroid_llm_LlamaNative_stop(JNIEnv*, jobject, jlong h) {
    if (h) reinterpret_cast<Session*>(h)->stop = true;
}

extern "C" JNIEXPORT void JNICALL
Java_com_localdroid_llm_LlamaNative_free(JNIEnv*, jobject, jlong h) {
    auto* s = reinterpret_cast<Session*>(h);
    if (!s) return;
    if (s->smpl)  llama_sampler_free(s->smpl);
    if (s->ctx)   llama_free(s->ctx);
    if (s->model) llama_model_free(s->model);
    delete s;
}
