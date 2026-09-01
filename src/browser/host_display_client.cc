#include "carbonyl/src/browser/host_display_client.h"

#include <utility>

#include "base/command_line.h"
#include "mojo/public/cpp/system/platform_handle.h"
#include "skia/ext/platform_canvas.h"
#include "third_party/skia/include/core/SkColor.h"
#include "third_party/skia/include/core/SkRect.h"
#include "third_party/skia/src/core/SkDevice.h"
#include "ui/compositor/compositor.h"
#include "ui/gfx/skia_util.h"

#if BUILDFLAG(IS_WIN)
#include "skia/ext/skia_utils_win.h"
#endif

#include "carbonyl/src/browser/renderer.h"
#include "carbonyl/src/browser/x_mirror.h"

namespace carbonyl {

LayeredWindowUpdater::LayeredWindowUpdater(
    mojo::PendingReceiver<viz::mojom::LayeredWindowUpdater> receiver,
    gfx::AcceleratedWidget widget)
    : receiver_(this, std::move(receiver)),
      task_runner_(base::SingleThreadTaskRunner::GetCurrentDefault()),
      widget_(widget) {}

LayeredWindowUpdater::~LayeredWindowUpdater() = default;

void LayeredWindowUpdater::OnAllocatedSharedMemory(
    const gfx::Size& pixel_size,
    base::UnsafeSharedMemoryRegion region) {
  if (region.IsValid()) {
    shm_mapping_ = region.Map();
  }

  pixel_size_ = pixel_size;

  if (x_mirror::ShouldRenderCompositor(widget_)) {
    x_mirror::EnsureSize(pixel_size.width(), pixel_size.height());
  }
}

void LayeredWindowUpdater::Draw(const gfx::Rect& damage_rect,
                                DrawCallback callback) {
  const bool render_output = x_mirror::ShouldRenderCompositor(widget_);
  if (render_output && x_mirror::Enabled()) {
    x_mirror::Blit(shm_mapping_.GetMemoryAs<uint8_t>(), damage_rect.x(),
                   damage_rect.y(), damage_rect.width(), damage_rect.height());
  }

  if (render_output) {
    Renderer::GetCurrent()->DrawBitmap(
        shm_mapping_.GetMemoryAs<uint8_t>(), pixel_size_, damage_rect,
        base::BindOnce(
            [](scoped_refptr<base::SingleThreadTaskRunner> task_runner,
               DrawCallback callback) {
              task_runner->PostTask(FROM_HERE, std::move(callback));
            },
            task_runner_, std::move(callback)));
    return;
  }

  task_runner_->PostTask(FROM_HERE, std::move(callback));
}

HostDisplayClient::HostDisplayClient(ui::Compositor* compositor)
    : viz::HostDisplayClient(compositor->widget()),
      compositor_(compositor),
      widget_(compositor->widget()) {
  const base::CommandLine* command_line =
      base::CommandLine::ForCurrentProcess();
  if (command_line->HasSwitch("carbonyl-operator-window")) {
    if (widget_ != gfx::kNullAcceleratedWidget) {
      // Before the native host attaches, the synthetic headless compositor
      // owns terminal output. Afterwards the hosted widget owns both page
      // pixels and terminal output; stale synthetic damage is acknowledged
      // without allowing it to overwrite the native compositor's frame.
      x_mirror::AttachToWindow(widget_);
    }
  }
}

HostDisplayClient::~HostDisplayClient() {
  x_mirror::DetachFromWindow(widget_);
}

void HostDisplayClient::CreateLayeredWindowUpdater(
    mojo::PendingReceiver<viz::mojom::LayeredWindowUpdater> receiver) {
  layered_window_updater_ =
      std::make_unique<LayeredWindowUpdater>(std::move(receiver), widget_);
}

#if BUILDFLAG(IS_LINUX) && BUILDFLAG(SUPPORTS_OZONE_X11)
void HostDisplayClient::DidCompleteSwapWithNewSize(const gfx::Size& size) {
  compositor_->OnCompleteSwapWithNewSize(size);
}
#endif

#if BUILDFLAG(IS_MAC)
void HostDisplayClient::OnDisplayReceivedCALayerParams(
    const gfx::CALayerParams& ca_layer_params) {}
#endif

}  // namespace carbonyl
