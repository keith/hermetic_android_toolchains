#include <string>

extern "C" int thin_lto_value(void);

extern "C" int thin_lto_shared_value() {
  return std::to_string(thin_lto_value()).size();
}
