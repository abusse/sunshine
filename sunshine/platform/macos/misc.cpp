#include <arpa/inet.h>
#include <ifaddrs.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <net/if_dl.h>

#include <pwd.h>
#include <unistd.h>

#include <fstream>

#include "misc.h"
#include "sunshine/main.h"
#include "sunshine/platform/common.h"

#ifdef __GNUC__
#define SUNSHINE_GNUC_EXTENSION __extension__
#else
#define SUNSHINE_GNUC_EXTENSION
#endif

using namespace std::literals;
namespace fs = std::filesystem;

namespace platf {
using ifaddr_t = util::safe_ptr<ifaddrs, freeifaddrs>;

ifaddr_t get_ifaddrs() {
  ifaddrs *p { nullptr };

  getifaddrs(&p);

  return ifaddr_t { p };
}

fs::path appdata() {
  const char *homedir;
  if((homedir = getenv("HOME")) == nullptr) {
    homedir = getpwuid(geteuid())->pw_dir;
  }

  return fs::path { homedir } / ".config/sunshine"sv;
}

std::string from_sockaddr(const sockaddr *const ip_addr) {
  char data[INET6_ADDRSTRLEN];

  auto family = ip_addr->sa_family;
  if(family == AF_INET6) {
    inet_ntop(AF_INET6, &((sockaddr_in6 *)ip_addr)->sin6_addr, data,
      INET6_ADDRSTRLEN);
  }

  if(family == AF_INET) {
    inet_ntop(AF_INET, &((sockaddr_in *)ip_addr)->sin_addr, data,
      INET_ADDRSTRLEN);
  }

  return std::string { data };
}

std::pair<std::uint16_t, std::string> from_sockaddr_ex(const sockaddr *const ip_addr) {
  char data[INET6_ADDRSTRLEN];

  auto family = ip_addr->sa_family;
  std::uint16_t port;
  if(family == AF_INET6) {
    inet_ntop(AF_INET6, &((sockaddr_in6 *)ip_addr)->sin6_addr, data,
      INET6_ADDRSTRLEN);
    port = ((sockaddr_in6 *)ip_addr)->sin6_port;
  }

  if(family == AF_INET) {
    inet_ntop(AF_INET, &((sockaddr_in *)ip_addr)->sin_addr, data,
      INET_ADDRSTRLEN);
    port = ((sockaddr_in *)ip_addr)->sin_port;
  }

  return { port, std::string { data } };
}

std::string get_mac_address(const std::string_view &address) {
  auto ifaddrs = get_ifaddrs();

  for (auto pos = ifaddrs.get(); pos != nullptr; pos = pos->ifa_next) {
    if (pos->ifa_addr && address == from_sockaddr(pos->ifa_addr)) {
      BOOST_LOG(verbose) << "Looking for MAC of "sv << pos->ifa_name;

      struct ifaddrs *ifap, *ifaptr;
      unsigned char *ptr;
      std::string mac_address;

      if (getifaddrs(&ifap) == 0) {
        for (ifaptr = ifap; ifaptr != NULL; ifaptr = (ifaptr)->ifa_next) {
          if (!strcmp((ifaptr)->ifa_name, pos->ifa_name) && (((ifaptr)->ifa_addr)->sa_family == AF_LINK)) {
            ptr = (unsigned char *)LLADDR((struct sockaddr_dl *)(ifaptr)->ifa_addr);
            char buff[100];

            snprintf(buff, sizeof(buff), "%02x:%02x:%02x:%02x:%02x:%02x",
                     *ptr, *(ptr + 1), *(ptr + 2), *(ptr + 3), *(ptr + 4), *(ptr + 5));
            mac_address = buff;
            break;
          }
        }

        freeifaddrs(ifap);

        if (ifaptr != NULL) {
          BOOST_LOG(verbose) << "Found MAC of "sv << pos->ifa_name << ": "sv << mac_address;
          return mac_address;
        }
      }
    }
  }

  BOOST_LOG(warning)
    << "Unable to find MAC address for "sv << address;
  return "00:00:00:00:00:00"s;
}
} // namespace platf

