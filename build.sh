#!/bin/bash
# Автоматический скрипт сборки Fabric мода (CrystalAuraHvH 1.21.1)

echo "=== Шаг 1: Инициализация шаблона Fabric ==="
# Скачиваем чистый легковесный шаблон
git clone --depth 1 https://github.com template
mv template/* .
mv template/.* . 2>/dev/null
rm -rf template src/main/java/net/fabricmc/example

# Настраиваем версии под 1.21.1 (актуальный релиз ветки 1.21)
cat << 'EOF' > gradle.properties
org.gradle.jvmargs=-Xmx3G
minecraft_version=1.21.1
yarn_mappings=1.21.1+build.2
loader_version=0.16.10
fabric_version=0.104.0+1.21.1
mod_version=1.0.0
mod_group=com.hvh.addon
mod_id=hvhaddon
EOF

echo "=== Шаг 2: Создание структуры папок ==="
mkdir -p src/main/java/com/hvh/addon
mkdir -p src/main/resources

echo "=== Шаг 3: Запись конфигурации fabric.mod.json ==="
cat << 'EOF' > src/main/resources/fabric.mod.json
{
  "schemaVersion": 1,
  "id": "hvhaddon",
  "version": "1.0.0",
  "name": "HvH Crystal Addon",
  "description": "Ultra fast crystal aura for 1.21.1",
  "environment": "client",
  "entrypoints": {
    "main": [
      "com.hvh.addon.HvHAddon"
    ]
  },
  "mixins": [],
  "depends": {
    "fabricloader": ">=0.16.0",
    "minecraft": "~1.21.1",
    "java": ">=21"
  }
}
EOF

echo "=== Шаг 4: Запись Java-кода (HvHAddon.java) ==="
cat << 'EOF' > src/main/java/com/hvh/addon/HvHAddon.java
package com.hvh.addon;

import net.fabricmc.api.ModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keybinding.v1.KeyBindingHelper;
import net.minecraft.client.option.KeyBinding;
import net.minecraft.client.util.InputUtil;
import org.lwjgl.glfw.GLFW;

public class HvHAddon implements ModInitializer {
    private static KeyBinding toggleKey;

    @Override
    public void onInitialize() {
        toggleKey = KeyBindingHelper.registerKeyBinding(new KeyBinding(
            "key.hvh.crystal_aura", 
            InputUtil.Type.KEYSYM, 
            GLFW.GLFW_KEY_C, 
            "category.hvh"
        ));

        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            while (toggleKey.wasPressed()) {
                CrystalAuraHvH.toggle();
            }
            CrystalAuraHvH.onTick();
        });
    }
}
EOF

echo "=== Шаг 5: Запись Java-кода (CrystalAuraHvH.java) ==="
cat << 'EOF' > src/main/java/com/hvh/addon/CrystalAuraHvH.java
package com.hvh.addon;

import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.entity.decoration.EndCrystalEntity;
import net.minecraft.item.Items;
import net.minecraft.network.packet.c2s.play.PlayerInteractEntityC2SPacket;
import net.minecraft.network.packet.c2s.play.PlayerInteractBlockC2SPacket;
import net.minecraft.text.Text;
import net.minecraft.util.Hand;
import net.minecraft.util.hit.BlockHitResult;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Direction;
import net.minecraft.util.math.Vec3d;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class CrystalAuraHvH {
    private static final MinecraftClient mc = MinecraftClient.getInstance();
    public static boolean isActive = false;
    private static final ExecutorService threadPool = Executors.newFixedThreadPool(4);

    public static void toggle() {
        isActive = !isActive;
        if (mc.player != null) {
            mc.player.sendMessage(Text.of("§7[HvH] §fCrystalAura: " + (isActive ? "§aENABLED" : "§cDISABLED")), true);
        }
    }

    public static void onTick() {
        if (!isActive || mc.player == null || mc.world == null || mc.getNetworkHandler() == null) return;

        boolean hasCrystals = mc.player.getMainHandStack().isOf(Items.END_CRYSTAL) || mc.player.getOffHandStack().isOf(Items.END_CRYSTAL);
        if (!hasCrystals) return;

        threadPool.execute(() -> {
            try {
                Hand hand = mc.player.getMainHandStack().isOf(Items.END_CRYSTAL) ? Hand.MAIN_HAND : Hand.OFF_HAND;

                for (Entity entity : mc.world.getEntities()) {
                    if (entity instanceof EndCrystalEntity crystal) {
                        if (mc.player.squaredDistanceTo(crystal) <= 36.0) {
                            for (int i = 0; i < 6; i++) {
                                mc.getNetworkHandler().sendPacket(PlayerInteractEntityC2SPacket.attack(crystal, mc.player.isSneaking()));
                            }
                            mc.player.swingHand(hand);
                        }
                    }
                }

                BlockPos playerPos = mc.player.getBlockPos();
                int radius = 5;

                for (int x = -radius; x <= radius; x++) {
                    for (int y = -radius; y <= radius; y++) {
                        for (int z = -radius; z <= radius; z++) {
                            BlockPos targetPos = playerPos.add(x, y, z);
                            if (isValidPlace(targetPos)) {
                                BlockHitResult hitResult = new BlockHitResult(
                                    new Vec3d(targetPos.getX() + 0.5, targetPos.getY() + 1.0, targetPos.getZ() + 0.5),
                                    Direction.UP, targetPos, false
                                );
                                for (int i = 0; i < 6; i++) {
                                    mc.getNetworkHandler().sendPacket(new PlayerInteractBlockC2SPacket(hand, hitResult, 0));
                                }
                            }
                        }
                    }
                }
            } catch (Exception ignored) {}
        });
    }

    private static boolean isValidPlace(BlockPos pos) {
        if (mc.world == null) return false;
        return mc.world.getBlockState(pos).isOf(net.minecraft.block.Blocks.OBSIDIAN) || 
               mc.world.getBlockState(pos).isOf(net.minecraft.block.Blocks.BEDROCK);
    }
}
EOF

echo "=== Шаг 6: Настройка GitHub Actions для компиляции ==="
mkdir -p .github/workflows
cat << 'EOF' > .github/workflows/build.yml
name: Build Mod Jar
on: [push, workflow_dispatch]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4
      - name: Setup Java 21
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '21'
      - name: Run Project Generator
        run: chmod +x build.sh && ./build.sh
      - name: Compile Jar (Gradle)
        run: chmod +x gradlew && ./gradlew build
      - name: Upload Output Artifact
        uses: actions/upload-artifact@v4
        with:
          name: hvh-crystal-addon
          path: build/libs/*-shadow*.jar || build/libs/*.jar
EOF

echo "=== Проект успешно сгенерирован! ==="
