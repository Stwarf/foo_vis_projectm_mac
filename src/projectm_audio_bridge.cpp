#include "projectm_audio_bridge.h"

#include <algorithm>

namespace {
class capture_callback_impl : public playback_stream_capture_callback {
public:
    void on_chunk(const audio_chunk& chunk) override {
        projectm_audio_bridge::instance().dispatch_chunk(chunk);
    }
};

capture_callback_impl g_capture_callback;
} // namespace

projectm_audio_bridge& projectm_audio_bridge::instance() {
    static projectm_audio_bridge bridge;
    return bridge;
}

void projectm_audio_bridge::add_sink(projectm_audio_sink* sink) {
    if (sink == nullptr) {
        return;
    }

    std::lock_guard<std::mutex> lock(m_sink_mutex);
    if (std::find(m_sinks.begin(), m_sinks.end(), sink) == m_sinks.end()) {
        m_sinks.push_back(sink);
    }
}

void projectm_audio_bridge::remove_sink(projectm_audio_sink* sink) {
    std::lock_guard<std::mutex> lock(m_sink_mutex);
    m_sinks.erase(std::remove(m_sinks.begin(), m_sinks.end(), sink), m_sinks.end());
}

void projectm_audio_bridge::dispatch_chunk(const audio_chunk& chunk) {
    std::vector<projectm_audio_sink*> sinks;
    {
        std::lock_guard<std::mutex> lock(m_sink_mutex);
        sinks = m_sinks;
    }

    for (projectm_audio_sink* sink : sinks) {
        if (sink != nullptr) {
            sink->add_audio_chunk(chunk);
        }
    }
}

void projectm_audio_bridge::start() {
    if (!m_running && !core_api::is_shutting_down()) {
        playback_stream_capture::get()->add_callback(&g_capture_callback);
        m_running = true;
    }
}

void projectm_audio_bridge::stop() {
    if (m_running) {
        playback_stream_capture::get()->remove_callback(&g_capture_callback);
        m_running = false;
    }
}

bool projectm_audio_bridge::running() const {
    return m_running;
}

namespace {
class projectm_audio_shutdown : public initquit {
public:
    void on_quit() override {
        projectm_audio_bridge::instance().stop();
    }
};

FB2K_SERVICE_FACTORY(projectm_audio_shutdown);
} // namespace
