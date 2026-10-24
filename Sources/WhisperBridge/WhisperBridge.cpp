#include <whisper.h>

#include <algorithm>
#include <cstring>
#include <string>
#include <thread>

namespace {

struct VoiceBarWhisperContext {
    whisper_context *context = nullptr;
};

void copy_error(char *destination, int32_t capacity, const char *message) {
    if (destination == nullptr || capacity <= 0) {
        return;
    }

    const auto length = std::min<std::size_t>(
        std::strlen(message), static_cast<std::size_t>(capacity - 1));
    std::memcpy(destination, message, length);
    destination[length] = '\0';
}

}

extern "C" {

void *voicebar_whisper_create(const char *model_path,
                              char *error_buffer,
                              int32_t error_capacity) {
    if (model_path == nullptr || model_path[0] == '\0') {
        copy_error(error_buffer, error_capacity, "Путь к модели не задан.");
        return nullptr;
    }

    auto *wrapper = new VoiceBarWhisperContext();
    auto parameters = whisper_context_default_params();
    parameters.use_gpu = true;
    wrapper->context = whisper_init_from_file_with_params(model_path, parameters);
    if (wrapper->context == nullptr) {
        copy_error(error_buffer, error_capacity,
                   "whisper.cpp не смог загрузить модель.");
        delete wrapper;
        return nullptr;
    }

    return wrapper;
}

void voicebar_whisper_destroy(void *opaque_context) {
    auto *wrapper = static_cast<VoiceBarWhisperContext *>(opaque_context);
    if (wrapper == nullptr) {
        return;
    }

    whisper_free(wrapper->context);
    delete wrapper;
}

int32_t voicebar_whisper_transcribe(void *opaque_context,
                                    const float *samples,
                                    int32_t sample_count,
                                    const char *language,
                                    char *text_buffer,
                                    int32_t text_capacity,
                                    char *error_buffer,
                                    int32_t error_capacity) {
    auto *wrapper = static_cast<VoiceBarWhisperContext *>(opaque_context);
    if (wrapper == nullptr || wrapper->context == nullptr || samples == nullptr ||
        sample_count <= 0 || text_buffer == nullptr || text_capacity <= 0) {
        copy_error(error_buffer, error_capacity, "Некорректные аудиоданные.");
        return -1;
    }

    text_buffer[0] = '\0';
    auto parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    parameters.print_progress = false;
    parameters.print_realtime = false;
    parameters.print_timestamps = false;
    parameters.no_context = true;
    parameters.n_threads = 4;
    parameters.language = (language == nullptr || language[0] == '\0')
                              ? "auto"
                              : language;

    if (whisper_full(wrapper->context, parameters, samples,
                     static_cast<std::size_t>(sample_count)) != 0) {
        copy_error(error_buffer, error_capacity, "Ошибка распознавания аудио.");
        return -2;
    }

    std::size_t written = 0;
    const auto segment_count = whisper_full_n_segments(wrapper->context);
    for (int index = 0; index < segment_count; ++index) {
        const char *segment = whisper_full_get_segment_text(wrapper->context, index);
        if (segment == nullptr || segment[0] == '\0') {
            continue;
        }

        if (written > 0 && written + 1 < static_cast<std::size_t>(text_capacity)) {
            text_buffer[written++] = ' ';
        }

        const auto available = static_cast<std::size_t>(text_capacity) - written - 1;
        const auto length = std::min<std::size_t>(std::strlen(segment), available);
        std::memcpy(text_buffer + written, segment, length);
        written += length;
        text_buffer[written] = '\0';
        if (written + 1 >= static_cast<std::size_t>(text_capacity)) {
            break;
        }
    }

    return 0;
}

}
