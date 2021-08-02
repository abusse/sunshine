#include "sunshine/platform/common.h"
#include "sunshine/platform/macos/av_video.h"

#include "sunshine/config.h"
#include "sunshine/main.h"

namespace fs = std::filesystem;

namespace platf {
using namespace std::literals;

struct avdisplay_img_t : public img_t {
  // We have to retain the DataRef to an image for the image buffer
  // and release it when the image buffer is no longer needed
  // XXX: this should be replaced by a smart pointer with CFRelease as custom deallocator
  CFDataRef dataRef = nullptr;

  ~avdisplay_img_t() override {
    if(dataRef != NULL)
      CFRelease(dataRef);
    data = nullptr;
  }
};

struct avdisplay_attr_t : public display_t {
  AVVideo *display;
  CGDirectDisplayID display_id;

  ~avdisplay_attr_t() {
    [display release];
  }

  capture_e capture(snapshot_cb_t &&snapshot_cb, std::shared_ptr<img_t> img, bool *cursor) override {
    __block auto next_img = std::move(img);

    [display capture:^(CGImageRef imgRef) {
      CGDataProviderRef dataProvider = CGImageGetDataProvider(imgRef);

      CFDataRef dataRef = CGDataProviderCopyData(dataProvider);

      // XXX: next_img->img should be moved to a smart pointer with
      // the CFRelease as custon deallocator
      if((std::static_pointer_cast<avdisplay_img_t>(next_img))->dataRef != nullptr) {
        CFRelease((std::static_pointer_cast<avdisplay_img_t>(next_img))->dataRef);
      }

      (std::static_pointer_cast<avdisplay_img_t>(next_img))->dataRef = dataRef;
      next_img->data                                                 = (uint8_t *)CFDataGetBytePtr(dataRef);

      next_img->width       = CGImageGetWidth(imgRef);
      next_img->height      = CGImageGetHeight(imgRef);
      next_img->row_pitch   = CGImageGetBytesPerRow(imgRef);
      next_img->pixel_pitch = CGImageGetBitsPerPixel(imgRef) / 8;

      next_img = snapshot_cb(next_img);

      return next_img != nullptr;
    }];

    [display.captureStopped wait];

    return capture_e::ok;
  }

  std::shared_ptr<img_t> alloc_img() override {
    return std::make_shared<avdisplay_img_t>();
  }

  int dummy_img(img_t *img) override {
    auto imgRef = CGDisplayCreateImage(display_id);

    if(!imgRef)
      return -1;

    CGDataProviderRef dataProvider = CGImageGetDataProvider(imgRef);

    CFDataRef dataRef = CGDataProviderCopyData(dataProvider);

    ((avdisplay_img_t *)img)->dataRef = dataRef;
    img->data                         = (uint8_t *)CFDataGetBytePtr(dataRef);

    img->width       = CGImageGetWidth(imgRef);
    img->height      = CGImageGetHeight(imgRef);
    img->row_pitch   = CGImageGetBytesPerRow(imgRef);
    img->pixel_pitch = CGImageGetBitsPerPixel(imgRef) / 8;

    CFRelease(imgRef);

    return 0;
  }
};

std::shared_ptr<display_t> display(platf::mem_type_e hwdevice_type, const std::string &display_name, int framerate) {
  if(hwdevice_type != platf::mem_type_e::system && hwdevice_type != platf::mem_type_e::videotoolbox) {
    BOOST_LOG(error) << "Could not initialize display with the given hw device type."sv;
    return nullptr;
  }

  auto result = std::make_shared<avdisplay_attr_t>();

  int capture_width  = 0;
  int capture_height = 0;

  if(config::video.sw.width.has_value() && config::video.sw.height.has_value()) {
    capture_width  = config::video.sw.width.value();
    capture_height = config::video.sw.height.value();
    BOOST_LOG(info) << "Capturing with "sv << capture_width << "x"sv << capture_height;
  }

  result->display_id = CGMainDisplayID();
  if(!display_name.empty()) {
    auto display_array = [AVVideo displayNames];

    for(NSDictionary *item in display_array) {
      NSString *name = item[@"name"];
      if(name.UTF8String == display_name) {
        NSNumber *display_id = item[@"id"];
        result->display_id   = [display_id unsignedIntValue];
      }
    }
  }

  result->display = [[AVVideo alloc] initWithDisplay:result->display_id frameRate:framerate width:capture_width height:capture_height];

  if(!result->display) {
    BOOST_LOG(error) << "Video setup failed."sv;
    return nullptr;
  }

  auto tmp_image = result->alloc_img();
  if(result->dummy_img(tmp_image.get())) {
    result->width  = capture_width;
    result->height = capture_height;
  }
  else {
    result->width  = tmp_image->width;
    result->height = tmp_image->height;
  }

  return result;
}

std::vector<std::string> display_names() {
  __block std::vector<std::string> display_names;

  auto display_array = [AVVideo displayNames];

  display_names.reserve([display_array count]);
  [display_array enumerateObjectsUsingBlock:^(NSDictionary *_Nonnull obj, NSUInteger idx, BOOL *_Nonnull stop) {
    NSString *name = obj[@"name"];
    display_names.push_back(name.UTF8String);
  }];

  return display_names;
}
}