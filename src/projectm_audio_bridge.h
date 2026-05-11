#pragma once

#include "stdafx.h"

#include <mutex>
#include <vector>

class projectm_audio_sink {
public:
    virtual void add_audio_chunk(const audio_chunk& chunk) = 0;

protected:
    ~projectm_audio_sink() = default;
};

class projectm_audio_bridge {
public:
    static projectm_audio_bridge& instance();

    void add_sink(projectm_audio_sink* sink);
    void remove_sink(projectm_audio_sink* sink);
    void dispatch_chunk(const audio_chunk& chunk);
    void start();
    void stop();
    bool running() const;

private:
    projectm_audio_bridge() = default;
    projectm_audio_bridge(const projectm_audio_bridge&) = delete;
    projectm_audio_bridge& operator=(const projectm_audio_bridge&) = delete;

    mutable std::mutex m_sink_mutex;
    std::vector<projectm_audio_sink*> m_sinks;
    bool m_running = false;
};
