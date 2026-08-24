#!/bin/bash
rm -rf src gradle .gradle build gradle.properties build.gradle settings.gradle gradlew gradlew.bat fabric.mod.json mixins.json
git clone --depth 1 https://github.com .
rm -rf src/main/java/net/fabricmc/example

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

mkdir -p src/main/java/com/hvh/addon/mixin src/main/resources

cat << 'EOF' > src/main/resources/fabric.mod.json
{
  "schemaVersion": 1,
  "id": "hvhaddon",
  "version": "1.0.0",
  "name": "Choopa Mode Addon",
  "description": "Choopa Engine",
  "environment": "client",
  "entrypoints": { "main": [ "com.hvh.addon.HvHAddon" ] },
  "mixins": [ "hvhaddon.mixins.json" ],
  "depends": { "fabricloader": ">=0.16.0", "minecraft": ">=1.21.1", "java": ">=21" }
}
EOF

cat << 'EOF' > src/main/resources/hvhaddon.mixins.json
{
  "required": true,
  "package": "com.hvh.addon.mixin",
  "compatibilityLevel": "JAVA_21",
  "mixins": [ "InGameHudMixin" ],
  "injectors": { "defaultRequire": 1 }
}
EOF

cat << 'EOF' > src/main/java/com/hvh/addon/mixin/InGameHudMixin.java
package com.hvh.addon.mixin;
import com.hvh.addon.CrystalAuraHvH;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.hud.InGameHud;
import net.minecraft.client.render.RenderTickCounter;
import net.minecraft.item.Items;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(InGameHud.class)
public class InGameHudMixin {
    @Inject(method = "render", at = @At("TAIL"))
    private void onRenderHUD(DrawContext context, RenderTickCounter tickCounter, CallbackInfo ci) {
        MinecraftClient mc = MinecraftClient.getInstance();
        if (mc.player == null || mc.textRenderer == null) return;
        int startY = 10;
        String statusStr = CrystalAuraHvH.isActive ? "§aREADY" : "§cOFF";
        context.drawText(mc.textRenderer, "§7[§cChoopa Mode§7] Status: " + statusStr, 10, startY, 0xFFFFFF, true);
        if (CrystalAuraHvH.isActive) {
            float hp = mc.player.getHealth() + mc.player.getAbsorptionAmount();
            int totems = 0;
            for (int i = 0; i < 36; i++) {
                if (mc.player.getInventory().getStack(i).isOf(Items.TOTEM_OF_UNDYING)) totems++;
            }
            if (mc.player.getOffHandStack().isOf(Items.TOTEM_OF_UNDYING)) totems++;
            context.drawText(mc.textRenderer, "§7-> Crystals/Sec: §f" + CrystalAuraHvH.crystalSpeedTracker, 10, startY + 12, 0xFFFFFF, true);
            context.drawText(mc.textRenderer, "§7-> Totems Left: §e" + totems, 10, startY + 24, 0xFFFFFF, true);
            context.drawText(mc.textRenderer, "§7-> Health Engine: §d" + String.format("%.1f", hp) + " HP", 10, startY + 36, 0xFFFFFF, true);
            context.drawText(mc.textRenderer, "§7-> Shield Engine: §bVELOCITY ON", 10, startY + 48, 0xFFFFFF, true);
        }
    }
}
EOF

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
        toggleKey = KeyBindingHelper.registerKeyBinding(new KeyBinding("key.hvh.crystal_aura", InputUtil.Type.KEYSYM, GLFW.GLFW_KEY_C, "category.hvh"));
        ClientTickEvents.END_CLIENT_TICK.register(client -> {
            while (toggleKey.wasPressed()) { CrystalAuraHvH.toggle(); }
            CrystalAuraHvH.onTick();
        });
    }
}
EOF

cat << 'EOF' > src/main/java/com/hvh/addon/CrystalAuraHvH.java
package com.hvh.addon;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.entity.EntityType;
import net.minecraft.entity.LightningEntity;
import net.minecraft.entity.decoration.EndCrystalEntity;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.item.ItemStack;
import net.minecraft.item.Items;
import net.minecraft.network.packet.c2s.play.PlayerInteractEntityC2SPacket;
import net.minecraft.network.packet.c2s.play.PlayerInteractBlockC2SPacket;
import net.minecraft.network.packet.c2s.play.ClickSlotC2SPacket;
import net.minecraft.network.packet.c2s.play.PlayerMoveC2SPacket;
import net.minecraft.screen.ScreenHandler;
import net.minecraft.screen.slot.SlotActionType;
import net.minecraft.sound.SoundCategory;
import net.minecraft.sound.SoundEvents;
import net.minecraft.text.Text;
import net.minecraft.util.Hand;
import net.minecraft.util.hit.BlockHitResult;
import net.minecraft.util.math.BlockPos;
import net.minecraft.util.math.Direction;
import net.minecraft.util.math.Vec3d;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

public class CrystalAuraHvH {
    private static final MinecraftClient mc = MinecraftClient.getInstance();
    public static boolean isActive = false;
    public static int crystalSpeedTracker = 0;
    private static final ExecutorService pool = Executors.newFixedThreadPool(6);
    private static final AtomicBoolean proc = new AtomicBoolean(false);
    private static final Map<Entity, Boolean> dead = new ConcurrentHashMap<>();
    private static long lastReset = System.currentTimeMillis();
    private static int countSec = 0;

    public static void toggle() {
        isActive = !isActive;
        if (mc.player != null) { mc.player.sendMessage(Text.of("§7[Choopa Mode] " + (isActive ? "§aREADY" : "§cOFF")), true); }
    }

    public static void onTick() {
        if (!isActive || mc.player == null || mc.world == null || mc.getNetworkHandler() == null) return;
        if (System.currentTimeMillis() - lastReset >= 1000) {
            crystalSpeedTracker = countSec;
            countSec = 0;
            lastReset = System.currentTimeMillis();
        }
        if (mc.player.horizontalCollision) {
            Vec3d v = mc.player.getVelocity();
            mc.player.setVelocity(v.x, 0.42, v.z);
        }
        if (proc.get()) return;
        proc.set(true);
        pool.execute(() -> {
            try {
                if (mc.player == null || mc.world == null || mc.getNetworkHandler() == null) return;
                float hp = mc.player.getHealth() + mc.player.getAbsorptionAmount();
                boolean holds = mc.player.getOffHandStack().isOf(Items.TOTEM_OF_UNDYING);
                if (hp <= 13.5f || !holds) {
                    if (!holds) {
                        int tSlot = findTotemSlot();
                        if (tSlot != -1) {
                            click(tSlot, 0, SlotActionType.PICKUP);
                            click(45, 0, SlotActionType.PICKUP);
                            click(tSlot, 0, SlotActionType.PICKUP);
                        }
                    }
                    return;
                }
                ScreenHandler sh = mc.player.currentScreenHandler;
                if (sh != null && (sh.slots.size() == 63 || sh.slots.size() == 90)) {
                    for (int i = 0; i < (sh.slots.size() == 63 ? 26 : 53); i++) {
                        ItemStack s = sh.getSlot(i).getStack();
                        if (!s.isEmpty() && (s.isOf(Items.END_CRYSTAL) || s.isOf(Items.TOTEM_OF_UNDYING))) { click(i, 0, SlotActionType.QUICK_MOVE); }
                    }
                }
                for (Entity e : mc.world.getEntities()) {
                    if (e instanceof PlayerEntity enemy && enemy != mc.player) {
                        if (!enemy.isAlive() || enemy.getHealth() <= 0f) {
                            if (!dead.containsKey(enemy)) {
                                dead.put(enemy, true);
                                mc.execute(() -> {
                                    if (mc.world != null) {
                                        LightningEntity b = new LightningEntity(EntityType.LIGHTNING_BOLT, mc.world);
                                        b.refreshPositionAfterTeleport(enemy.getX(), enemy.getY(), enemy.getZ());
                                        mc.world.addEntity(b);
                                    }
                                });
                            }
                            continue;
                        }
                        if (mc.player.squaredDistanceTo(enemy) <= 17.64) {
                            double j = mc.player.getYaw() + (Math.random() > 0.5 ? 90.0 : -90.0);
                            mc.getNetworkHandler().sendPacket(new PlayerMoveC2SPacket.LookAndOnGround((float) j, 90f, mc.player.isOnGround()));
                            for (int k = 0; k < 4; k++) { mc.getNetworkHandler().sendPacket(PlayerInteractEntityC2SPacket.attack(enemy, mc.player.isSneaking())); }
                            mc.execute(() -> {
                                if (mc.world != null && mc.player != null) {
                                    mc.world.playSound(mc.player, mc.player.getX(), mc.player.getY(), mc.player.getZ(), SoundEvents.UI_BUTTON_CLICK.value(), SoundCategory.PLAYERS, 1f, 1.5f);
                                }
                            });
                            mc.player.swingHand(Hand.MAIN_HAND);
                            break;
                        }
                    }
                }
                dead.keySet().removeIf(e -> !mc.world.getEntities().toCollection().contains(e));
    Hand h = mc.player.getMainHandStack().isOf(Items.END_CRYSTAL) ? Hand.MAIN_HAND : (mc.player.getOffHandStack().isOf(Items.END_CRYSTAL) ? Hand.OFF_HAND : null);if (h == null) return;for (Entity e : mc.world.getEntities()) {if (e instanceof EndCrystalEntity cry) {if (mc.player.squaredDistanceTo(cry) <= 36.0) {for (int i = 0; i < 4; i++) {mc.getNetworkHandler().sendPacket(PlayerInteractEntityC2SPacket.attack(cry, mc.player.isSneaking()));countSec++;}mc.player.swingHand(h);break;}}}BlockPos pPos = mc.player.getBlockPos();int r = 5;BlockPos[] offsets = {pPos.north(), pPos.south(), pPos.east(), pPos.west() };for (BlockPos pos : offsets) {if (mc.world.getBlockState(pos).isAir() && mc.world.getBlockState(pos.down()).isSolid()) {BlockHitResult bhr = new BlockHitResult(new Vec3d(pos.getX() + 0.5, pos.getY() + 0.5, pos.getZ() + 0.5), Direction.UP, pos, false);mc.getNetworkHandler().sendPacket(new PlayerInteractBlockC2SPacket(Hand.MAIN_HAND, bhr, 0));}}for (int x = -r; x <= r; x++) {for (int y = -r; y <= r; y++) {for (int z = -r; z <= r; z++) {BlockPos tPos = pPos.add(x, y, z);if (isValidPlace(tPos)) {BlockHitResult bhr = new BlockHitResult(new Vec3d(tPos.getX() + 0.5, tPos.getY() + 1.0, tPos.getZ() + 0.5), Direction.UP, tPos, false);mc.getNetworkHandler().sendPacket(new PlayerInteractBlockC2SPacket(h, bhr, 0));mc.getNetworkHandler().sendPacket(new PlayerInteractBlockC2SPacket(h, bhr, 0));mc.player.swingHand(h);}}}}} catch (Exception ignored) {} finally {proc.set(false);}});}private static void click(int id, int b, SlotActionType a) {if (mc.getNetworkHandler() == null || mc.player == null) return;mc.getNetworkHandler().sendPacket(new ClickSlotC2SPacket(mc.player.currentScreenHandler.syncId, mc.player.currentScreenHandler.getRevision(), id, b, a, mc.player.currentScreenHandler.getSlot(id).getStack().copy(), mc.player.getInventory().getCursorStack().copy()));}private static int findTotemSlot() {for (int i = 0; i < 36; i++) {if (mc.player.getInventory().getStack(i).isOf(Items.TOTEM_OF_UNDYING)) { return i < 9 ? i + 36 : i; }}return -1;}private static boolean isValidPlace(BlockPos p) {if (mc.world == null) return false;return (mc.world.getBlockState(p).isOf(net.minecraft.block.Blocks.OBSIDIAN) || mc.world.getBlockState(p).isOf(net.minecraft.block.Blocks.BEDROCK)) && mc.world.getBlockState(p.up()).isAir();}}EOFchmod +x gradlew./gradlew build
