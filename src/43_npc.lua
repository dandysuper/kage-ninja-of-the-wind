-- ============================================================================
--  43 NPCs - townsfolk who wander, face you, show "!"/"?" quest markers,
--  run shops and inns, and chat (lines vary by region and story progress).
-- ============================================================================
NPC = {}
NPCK = {
  sensei = { spr = "eld_f1", name = "Sensei Hayate" },
  shopkeep = { spr = "vil_f1", pm = { [C_BLUE] = C_WOOD, [C_INDIGO] = C_BROWN } },
  innkeep = { spr = "wom_f1", pm = { [C_PINK] = C_GOLD, [C_WHITE] = C_CREAM } },
  farmer = { spr = "vil_f1", pm = { [C_BLUE] = C_GREEN, [C_INDIGO] = C_DKGRN } },
  villager = { spr = "vil_f1" },
  woman = { spr = "wom_f1" },
  child = { spr = "kid_f1" },
  lady = { spr = "lady_f1", name = "Lady Sayo" },
  captain = { spr = "grd_f1", pm = { [C_RED] = C_INDIGO, [C_GOLD] = C_WHITE }, name = "Captain Ishida" },
  guard = { spr = "grd_f1", name = "Castle Guard" },
  smith = { spr = "vil_f1", pm = { [C_BLUE] = C_NIGHT, [C_INDIGO] = C_GRAY, [C_TAN] = C_GRAY, [C_WOOD] = C_BROWN } },
  teamaster = { spr = "eld_f1", pm = { [C_GRAY] = C_GREEN, [C_WHITE] = C_GRAY } },
  monk = { spr = "eld_f1", pm = { [C_GRAY] = C_GOLD, [C_WHITE] = C_CREAM, [C_BROWN] = C_WOOD } },
  tailor = { spr = "wom_f1", pm = { [C_PINK] = C_BLUE, [C_RED] = C_GOLD } },
  woodcutter = { spr = "vil_f1", pm = { [C_BLUE] = C_DKGRN, [C_INDIGO] = C_BROWN } },
  fisher = { spr = "vil_f1", pm = { [C_BLUE] = C_INDIGO, [C_RED] = C_WHITE } },
  merchant = { spr = "vil_f1", pm = { [C_BLUE] = C_RED, [C_INDIGO] = C_BROWN } },
  tanuki = { spr = "fox1", pm = { [C_WOOD] = C_BROWN, [C_TAN] = C_WOOD, [C_CREAM] = C_TAN }, name = "Ponta the Tanuki" },
}
local VARIANTS = {
  villager = { nil, { [C_BLUE] = C_GREEN, [C_INDIGO] = C_DKGRN }, { [C_BLUE] = C_WOOD, [C_INDIGO] = C_BROWN }, { [C_BLUE] = C_GRAY } },
  woman = { nil, { [C_PINK] = C_BLUE, [C_RED] = C_INDIGO }, { [C_PINK] = C_LIME, [C_RED] = C_GREEN }, { [C_PINK] = C_GOLD } },
}
local NAMES = { "Hiro", "Saki", "Jiro", "Yumi", "Ken", "Rin", "Sota", "Hana", "Daichi", "Emi", "Kaito", "Nao", "Riku", "Aoi" }

-- flavour lines by role, then by region
local LINES = {
  villager = { "Have you tried the onigiri at the inn? Best in the province.", "The nights grow longer since the Treasures vanished.",
    "Keep a torch handy. The dark has teeth.", "I saw a tiny white spirit on a rock pillar. A kodama!",
    "Bandits camp along the roads. Travel by day.", "Climb the pagodas - you can see the whole land from up there." },
  guard = { "Halt! ...Ah, a shinobi. Carry on.", "The Shogun's castle is closed to commoners.", "Oni were sighted near the eastern coast.",
    "We guard the walls. You guard the roads." },
  child = { "Ninja! Ninja! Can you jump on the roofs?", "Mama says yurei only come out at night.", "I want a kite like yours!" },
  woman = { "Sakura petals make lovely dango.", "The tea master in Kyo pays well for wild herbs.", "Rest at an inn and you'll wake refreshed." },
  monk = { "Kneel at a Jizo once a day. He will mend your wounds.", "Spirit shrines test the body. Spirit orbs reward the brave.",
    "Four orbs offered to the Kannon statue in Kyo grant great strength." },
}
local REGIONLINES = {
  ["Mount Fuyu"] = { "Without a fur cloak the mountain wind will freeze you.", "Hot tea or stew keeps the cold away for a while." },
  ["Minato Coast"] = { "Kappa! Offer one a cucumber and it might spare you.", "The bridge to Onigashima is sealed with sacred rope." },
  ["Whispering Bamboo"] = { "Bamboo shoots, boiled, give you strength.", "Spider silk is strong as steel." },
}

function NPC.spawnAll()
  local n = 0
  for _, s in ipairs(NPCSPAWN) do
    n = n + 1
    local K = NPCK[s.kind] or NPCK.villager
    local d = s.data or {}
    local pmt = K.pm
    local v = VARIANTS[s.kind]
    if v and not d.name then pmt = v[1 + n % #v] end
    local e = Ent.add({ kind = "npc", role = s.kind, id = d.id or s.kind, x = s.x, y = s.y, hx = s.x, hy = s.y, r = 3, step = 4.5,
      name = d.name or K.name or NAMES[1 + (n * 7) % #NAMES], data = d, spr = K.spr, pm = pmt and Pal.mk(pmt) or nil,
      dir = math.pi / 2, wander = (s.kind == "villager" or s.kind == "woman" or s.kind == "child" or s.kind == "guard") and 18 or 4,
      dry = true, always = false })
    e.update = NPC.update
    e.draw = NPC.draw
    e.interact = NPC.talk
  end
end

function NPC.find(id)
  for _, e in ipairs(ENTS) do
    if e.alive and e.kind == "npc" and e.id == id then return e end
  end
end

function NPC.update(e)
  local p = P
  local d = dist(e.x, e.y, p.x, p.y)
  if Dialog.active and Dialog.who == e then
    e.vx, e.vy = 0, 0
    e.dir = math.atan(p.y - e.y, p.x - e.x)
  elseif d < 26 then
    e.vx, e.vy = e.vx * 0.7, e.vy * 0.7
    e.dir = math.atan(p.y - e.y, p.x - e.x)
  else
    e.wt = (e.wt or 0) - 1
    if e.wt <= 0 then
      e.wt = rnd(90, 240)
      if rnd() < 0.6 and e.wander > 4 then
        local a = rnd() * TAU
        e.tx, e.ty = e.hx + math.cos(a) * rnd(4, e.wander), e.hy + math.sin(a) * rnd(4, e.wander)
      else
        e.tx = nil
      end
    end
    if e.tx then
      local dx, dy = e.tx - e.x, e.ty - e.y
      local l = math.sqrt(dx * dx + dy * dy)
      if l > 2 then
        e.vx, e.vy = dx / l * 0.35, dy / l * 0.35
        e.dir = math.atan(dy, dx)
      else
        e.tx = nil
        e.vx, e.vy = 0, 0
      end
    else
      e.vx, e.vy = 0, 0
    end
  end
  Ent.physics(e)
end

function NPC.draw(e)
  local r = SPR[e.spr]
  if not r then return end
  local moving = math.abs(e.vx) + math.abs(e.vy) > 0.05
  local _, flip = Ent.view(e.dir)
  local bob = moving and ((e.t // 8) % 2) or 0
  Ent.shadow(e, 4)
  Render.bill(r, e.x, e.y, e.z + bob * 0.8, moving and ((e.t // 8) % 2 == 0) or flip, e.pm)
  Render.setPM(nil)
  -- quest marker
  local mk = Quest.marker(e)
  if mk then
    local mr = SPR[mk]
    local sx, sy = proj(e.x, e.y, e.z)
    local y = sy - r[4] - 10 + math.sin(Frame / 10) * 1.5
    blit(mr, flr(sx - mr[3] / 2), flr(y))
  end
end

function NPC.chatter(e)
  local pool = LINES[e.role] or LINES.villager
  local reg = REG[WR[cidx(clamp(flr(e.x / 8), 0, 239), clamp(flr(e.y / 8), 0, 111))]]
  local extra = reg and REGIONLINES[reg.name]
  if extra and rnd() < 0.5 then pool = extra end
  e.line = ((e.line or rnd(#pool)) % #pool) + 1
  Dialog.say(e.name, pool[e.line], nil, e)
end

function NPC.talk(e)
  Sfx.play("talk")
  if Quest.onTalk(e) then return end
  local d = e.data
  if d.shop then
    Dialog.say(e.name, "Welcome! Take a look.", function() Menu.open("shop", { shop = d.shop, who = e }) end, e)
  elseif d.inn then
    Dialog.ask(e.name, "A warm futon for " .. d.inn .. " ryo? You'll wake at dawn, fully rested.", { "Rest", "No thanks" }, function(c)
      if c == 1 then
        if P.ryo >= d.inn then
          P.ryo = P.ryo - d.inn
          Game.sleep(e)
        else
          Dialog.say(e.name, "Oh dear, you're short on ryo.", nil, e)
        end
      end
    end, e)
  elseif e.role == "tanuki" then
    if P.seeds >= 3 and Inv.size < 16 then
      P.seeds = P.seeds - 3
      Inv.size = math.min(16, Inv.size + 2)
      Sfx.play("upgrade")
      Dialog.say(e.name, "Pon pon! Three kodama seeds! I'll stitch your bag bigger. (Inventory +2 slots)", nil, e)
    else
      Dialog.say(e.name, "Kodama hide atop stone pillars and deep in the woods. Bring me 3 of their seeds and I'll enlarge your bag! (You have " .. P.seeds .. ")", nil, e)
    end
  elseif e.role == "guard" and Quest.state("mq4") ~= "done" and dist(e.x, e.y, POI.bridge.x, POI.bridge.y) < 40 then
    Dialog.say(e.name, "The bridge is sealed by the Shogun's order.", nil, e)
  else
    NPC.chatter(e)
  end
end

-- the lost cat wanders near the bamboo forest until rescued
function NPC.spawnCat()
  if Quest.state("cat") == "done" or Inv.has("cat") then return end
  local c = POI.cat
  local e = Ent.add({ kind = "npc", role = "cat", id = "tama", name = "Tama", x = c.x, y = c.y, hx = c.x, hy = c.y, r = 2, spr = "cat1",
    wander = 14, dir = 0, dry = true })
  e.update = NPC.update
  e.draw = NPC.draw
  e.interact = function(self)
    if Quest.active("cat") then
      self.alive = false
      Inv.add("cat", 1)
      Sfx.play("cat")
      Quest.event("found", "cat")
      Dialog.say("Tama", "Mrrow! (Tama hops into your arms.)")
    else
      Dialog.say("Tama", "Mrrow? The cat looks lost.")
    end
  end
end
