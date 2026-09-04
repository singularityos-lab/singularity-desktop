BUILD_DIR = build
LABWC_DIR = subprojects/labwc
LABWC_BUILD = $(LABWC_DIR)/build
GESTURE_DIR = subprojects/singularity-gestures

all: compile

$(BUILD_DIR)/build.ninja: | gesture-runtime
	meson setup $(BUILD_DIR) || { rm -rf $(BUILD_DIR); meson setup $(BUILD_DIR); }

$(LABWC_BUILD)/build.ninja:
	meson setup $(LABWC_BUILD) $(LABWC_DIR) --prefix=/usr --buildtype=release -Dxwayland=enabled --force-fallback-for=wlroots-0.20 || { rm -rf $(LABWC_BUILD); meson setup $(LABWC_BUILD) $(LABWC_DIR) --prefix=/usr --buildtype=release -Dxwayland=enabled --force-fallback-for=wlroots-0.20; }

labwc: $(LABWC_BUILD)/build.ninja
	meson compile -C $(LABWC_BUILD)

compile: gesture-runtime $(BUILD_DIR)/build.ninja labwc
	ninja -C $(BUILD_DIR) subprojects/libsingularity/Singularity-1.0.gir
	mkdir -p $(HOME)/.local/share/gir-1.0
	cp $(BUILD_DIR)/subprojects/libsingularity/Singularity-1.0.gir $(HOME)/.local/share/gir-1.0/
	meson compile -C $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR) $(LABWC_BUILD)

install: compile
	@if [ -n "$$container" ]; then \
		echo "Inside container: bundling host libraries..."; \
		mkdir -p $(BUILD_DIR)/extra-libs; \
		find /usr/lib /usr/local/lib -name "libsfdo*.so*" -exec cp -a {} $(BUILD_DIR)/extra-libs/ \; 2>/dev/null || true; \
		find /usr/lib /usr/local/lib -name "libgtk4-layer-shell*.so*" -exec cp -a {} $(BUILD_DIR)/extra-libs/ \; 2>/dev/null || true; \
		find /usr/lib /usr/local/lib -name "libpeas-2*.so*" -exec cp -a {} $(BUILD_DIR)/extra-libs/ \; 2>/dev/null || true; \
	fi
	bash scripts/deploy-to-host.sh

run: compile
	mkdir -p $(BUILD_DIR)/share/applications
	mkdir -p $(BUILD_DIR)/share/icons/hicolor/scalable/apps
	cp data/*.desktop $(BUILD_DIR)/share/applications/
	cp -r data/icons/* $(BUILD_DIR)/share/icons/
	gtk-update-icon-cache -f -t $(BUILD_DIR)/share/icons/hicolor

reconfigure:
	meson setup $(BUILD_DIR) --reconfigure
	meson setup $(LABWC_BUILD) $(LABWC_DIR) --reconfigure --force-fallback-for=wlroots-0.20

schemas:
	glib-compile-schemas data/

install-session:
	@if [ -n "$$container" ]; then \
		host-spawn run0 bash $(CURDIR)/subprojects/singularity-session/scripts/install-session.sh; \
		host-spawn run0 bash $(CURDIR)/subprojects/singularity-session/scripts/install-gdm-config.sh; \
	else \
		run0 bash $(CURDIR)/subprojects/singularity-session/scripts/install-session.sh; \
		run0 bash $(CURDIR)/subprojects/singularity-session/scripts/install-gdm-config.sh; \
	fi

deploy-host:
	@echo "NOTE: 'make deploy-host' is deprecated and now runs 'make install';"
	@echo "      the install and deploy processes have been unified."
	@$(MAKE) install

gesture-runtime:
	@test -f $(GESTURE_DIR)/runtime/libmediapipe.so \
		-a -f $(GESTURE_DIR)/runtime/hand_landmarker.task \
		-a -f $(GESTURE_DIR)/runtime/face_landmarker.task \
		-a -f $(GESTURE_DIR)/runtime/libonnxruntime.so \
		-a -f $(GESTURE_DIR)/runtime/mobileone_s0_gaze.onnx \
		-a -f $(GESTURE_DIR)/runtime/include/onnxruntime_c_api.h \
		-a -f $(GESTURE_DIR)/runtime/include/onnxruntime_ep_c_api.h \
		|| bash $(GESTURE_DIR)/scripts/bootstrap-runtime.sh

install-greeter:
	@if [ -n "$$container" ]; then \
		host-spawn run0 bash $(CURDIR)/scripts/install-greeter.sh; \
	else \
		run0 bash $(CURDIR)/scripts/install-greeter.sh; \
	fi

.PHONY: all compile labwc gesture-runtime clean install run reconfigure schemas deploy-host install-session install-greeter
