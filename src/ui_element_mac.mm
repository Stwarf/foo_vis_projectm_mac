#import "stdafx.h"
#import "projectm_view.h"

namespace {
constexpr GUID guid_projectm_mac_element =
    {0xe6ad3abd, 0x662f, 0x4954, {0xb2, 0x0a, 0x30, 0xc6, 0xda, 0xc7, 0x3f, 0xf1}};

class projectm_mac_ui_element : public ui_element_mac {
public:
    service_ptr instantiate(service_ptr arg) override {
        (void)arg;
        ProjectMViewController* controller = [ProjectMViewController new];
        return fb2k::wrapNSObject(controller);
    }

    bool match_name(const char* name) override {
        return pfc::stricmp_ascii(name, "projectM") == 0 ||
               pfc::stricmp_ascii(name, "projectM Visualisation") == 0;
    }

    fb2k::stringRef get_name() override {
        return fb2k::makeString("projectM Visualisation");
    }

    GUID get_guid() override {
        return guid_projectm_mac_element;
    }
};

FB2K_SERVICE_FACTORY(projectm_mac_ui_element);
} // namespace
