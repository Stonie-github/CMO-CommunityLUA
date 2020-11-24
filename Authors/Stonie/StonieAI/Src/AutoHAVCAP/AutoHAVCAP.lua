--Stonie's Command Mission AI suite : HAVCAP Response AI V0.1
--This script will lunch a fighter squadron to protect high value assets when it estimates an incoming contact may threaten it.

-- Time for self to target at given speed and heading straight for it
function time_to_target(self, target)
    return Tool_Range(self.guid, target.guid) / self.speed
end

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

function lunch_havcap_mission(combat_ac, hva_ac, script_side, mission_name)

    -- Add a tracking reference point 1 mile in front of unit
    HAVUnit = ScenEdit_GetUnit(hva_ac)
    local havLocation = ScenEdit_AddReferencePoint( {side=script_side.name, RelativeTo=HAVUnit.name, bearingtype='rotating', bearing=HAVUnit.heading ,distance=5,highlighted=true })

    -- Add a mission for the HAVCAP asset based on the reference point, Assign CAP
    CAPUnit = ScenEdit_GetUnit(combat_ac)
    local script_mission = ScenEdit_AddMission(script_side.name,mission_name, 'patrol',{type='AAW', zone={havLocation.name}})
    local status = ScenEdit_AssignUnitToMission(CAPUnit.name, script_mission.name)

end

-------------------- START OF SCRIPT

SIDENAME = "Opfor"
PLAYERSIDE = "Bluefor"

local threatlist = {}
local threat_count = 0
--mission_go = false
--mission_launched = false


--------------------------------------------- ASSETS --------------------------------------
-- Example of hardcoding
HVALIST = { {name='SIGINT #1', side=SIDENAME}, {name="SIGINT #2", side="Opfor"}, { name="SIGINT #3", side="opfor" }, {name="SIGINT #4", side = "Opfor" }}
CAPLIST = { {name="Rusky #1", side="Opfor"}, {name = "Rusky #2", side="Opfor"}}

--------------------------------------------- SETUP ---------------------------------------
local script_side = VP_GetSide({name=SIDENAME})
local opposing_side = VP_GetSide({name=PLAYERSIDE})
local CAPLIST_LOCATION = 0
local HAVCAP_MISSION_NAME = "HAVCAP Mission"

---------------------------- CREATE THREATLIST ---------------------------
local all_contacts = script_side.contacts
for k,v in ipairs(all_contacts) do
    local script_contact = VP_GetContact({guid=all_contacts[k].guid})
    if script_contact.type == 'Air' then
        table.insert(threatlist, v)
        threat_count = threat_count + 1
    end
end

---------------------------- EVALUATE THREATS ----------------------------

local hav_unit = ScenEdit_GetUnit(HVALIST[1])
for k,v in ipairs(threatlist) do
    local threat = VP_GetContact({guid=threatlist[k].guid})
    local int_mission_go = estimate_intercept_threat_vs_asset(threat, hav_unit, 0.11, 0.023, 50)
    --print(int_mission_go)
    if (int_mission_go == true) then
        mission_go = true -- Set global
        break
    end
end

--print(mission_go)
--print(mission_launched)

if ((mission_go == true) and ((mission_launched == false) or (mission_launched == nil))) then
    print("Launcing mission")
    mission_launched = true
    lunch_havcap_mission(CAPLIST[2], HVALIST[1], script_side, HAVCAP_MISSION_NAME)
else
    print("No mission launched")
end
