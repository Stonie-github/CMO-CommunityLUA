--Stonie's Command Mission AI suite : HAVCAP Response AI V0.1
--This script will lunch a fighter squadron to protect high value assets when it estimates an incoming contact may threaten it.

-- Time for Unit: self to reach Unit: target at the speed self is on as if it were heading straight for it
function time_to_target(self, target)
    return Tool_Range(self.guid, target.guid) / self.speed
end

--Time for Unit: self to reach Unit: target at the speed self is on as if it were heading straight for it and a 
--distance reduction of margin : NM was applied
-- Example: time = time_to_target_with_margin(Unit, Unit, 10) 
function time_to_target_with_margin(self, target, margin)
    --local time_to_target = time_to_target(self, target)
    --local time_margin_budget = 
    local distance = Tool_Range(self.guid, target.guid)
    if ((distance-margin) > 0) then
        return (distance-margin) / self.speed
    else
        return 0
    end
end

-- Give a true/false respsponse as to if the Unit: threat, can reach distance: NM, from Unit:hav_asset, within the
-- time cap_time_to_area (Hours) + margin (Hours)
-- Example:  bool = estimate_intercept_threat_vs_asset(Unit, Unit, 0.5, 0.1, 50)
function estimate_intercept_threat_vs_asset (threat, hav_asset, cap_time_to_area, margin, distance )
        local threat_detected = false
        local threat_time_to_hva = time_to_target_with_margin(threat, hav_asset, distance)

        -- How far can the threat go in the time it takes for CAP to arrive
        local threat_coverage = (cap_time_to_area+margin)*threat.speed

        if ((cap_time_to_area - margin) > threat_time_to_hva) then
            --print("CAP will beat threat to area by " .. ((cap_time_to_area + margin)-threat_time_to_hva) .. " Hours")
            return false
        end

        local max_distance = math.ceil(threat_coverage)
        local interval = math.ceil(max_distance/10)
        for dist = 10,max_distance,interval do
            -- Create test point dist from threat bearing
            local intercept = World_GetPointFromBearing({latitude=threat.latitude, longitude=threat.longitude, distance=dist, bearing=threat.heading})
            -- Find distance from point to high value asset
            local point_distance = Tool_Range({ latitude=hav_asset.latitude, longitude=hav_asset.longitude},{ latitude=intercept.latitude, longitude=intercept.longitude })
            -- Debug to show points
            --local intercept_point = ScenEdit_AddReferencePoint( {side=script_side.name, longitude=intercept.longitude, latitude=intercept.latitude, highlighted=true })
            
            --print(point_distance)
            -- Check if distance is less than criteria
            if (point_distance < distance) then
                return true
            end
        end
        return false
end

-- Launch a HAVCAP mission with Unit: combat_ac, towards Unit:hva_ac, mission belongs to Side:script_side and mission name is a string
function lunch_havcap_mission(combat_ac, hva_ac, script_side, mission_name)

    -- Add a tracking reference point 1 mile in front of unit
    HAVUnit = ScenEdit_GetUnit(hva_ac)
    local havLocation = ScenEdit_AddReferencePoint( {side=script_side.name, RelativeTo=HAVUnit.name, bearingtype='rotating', bearing=HAVUnit.heading ,distance=5,highlighted=true })

    -- Add a mission for the HAVCAP asset based on the reference point, Assign CAP
    CAPUnit = ScenEdit_GetUnit(combat_ac)
    local script_mission = ScenEdit_AddMission(script_side.name,mission_name, 'patrol',{type='AAW', zone={havLocation.name}})
    local status = ScenEdit_AssignUnitToMission(CAPUnit.name, script_mission.name)
end

-- Populate the table passed to this function with air contacts with contacts from side.contacts
function sai_populate_air_threat_list(table_to_populate, contact_list)
    local num_air_contacts = 0
    for k,v in ipairs(contact_list) do
        local contact = VP_GetContact({guid=v.guid})
        if contact.type == 'Air' then
            table.insert(table_to_populate, v)
            num_air_contacts = num_air_contacts + 1
        end
    end
    return num_air_contacts
end

-------------------- START OF SCRIPT --------------------------------------------------------

SIDENAME = "Opfor"
PLAYERSIDE = "Bluefor"

-- Initialition
local threatlist = {}
local threat_count = 0 

-- Config
local dispatch_size = 2 -- How many CAPs
--mission_go = false
--mission_launched = false


--------------------------------------------- ASSETS --------------------------------------
-- Example of hardcoding
HVALIST = { {name='SIGINT #1', side=SIDENAME}, {name="SIGINT #2", side="Opfor"}, { name="SIGINT #3", side="opfor" }, {name="SIGINT #4", side = "Opfor" }}
CAPLIST = { {name="Rusky #1", side="Opfor"}, {name = "Rusky #2", side="Opfor"}}

--------------------------------------------- SETUP ---------------------------------------
local script_side = VP_GetSide({name=SIDENAME})
local opposing_side = VP_GetSide({name=PLAYERSIDE})
local HAVCAP_MISSION_NAME = "HAVCAP Mission"

-- Populate potential air threats
threat_count = sai_populate_air_threat_list(threatlist, script_side.contacts)
print("Found " .. threat_count .. " threats")

---------------------------- EVALUATE THREATS ----------------------------

-- Evaluate threats over both lists
for k,v in ipairs(HVALIST) do
	local hav_unit = ScenEdit_GetUnit(v)

    if (hav_unit.condition == 'Airborne') then  -- Skip flights that are not airborne
        print("Checking threat against asset " .. v.name)
        for k,v in ipairs(threatlist) do
            local threat = VP_GetContact({guid=v.guid})
            print("Checking " .. threat.name)
            local int_mission_go = estimate_intercept_threat_vs_asset(threat, hav_unit, 0.11, 0.023, 50)
            --print(int_mission_go)
            if (int_mission_go == true) then
                mission_go = true -- Set global
                break
            end
        end
    --else
        --print("Skipping Non Airborne Unit")
    end
end

if ((mission_go == true) and ((mission_launched == false) or (mission_launched == nil))) then
    print("Launcing mission")
    mission_launched = true
    lunch_havcap_mission(CAPLIST[2], HVALIST[1], script_side, HAVCAP_MISSION_NAME)
else
    print("No mission launched")
end
