#
# Matter_Plugin_2_Thermostat.be - implements the behavior for HVAC Thermostat
#
# Copyright (C) 2023  Stephan Hadinger & Theo Arends
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

import matter

# Matter plug-in for core behavior

#@ solidify:Matter_Plugin_Thermostat,weak

class Matter_Plugin_Thermostat : Matter_Plugin_Device  
  static var TYPE = "thermostat"                    # name of the plug-in in json
  static var DISPLAY_NAME = "Thermostat"            # display name of the plug-in

  static var UPDATE_COMMANDS = matter.UC_LIST(_class, "Thermostat")
  static var TYPES = { 0x0301: 2 }                  # Thermostat, rev 2

  static var CLUSTERS  = matter.consolidate_clusters(_class, {
    # 0x0003: inherited                                                               # Identify 1.2 p.16
    # 0x0004: inherited                                                               # Groups 1.3 p.21
    0x0201: [0,3,4,5,6,0x11,0x12,0x15,0x16,0x17,0x18,0x1B,0x1C,0x29,0xFFFC,0xFFFD],   # Thermostat p.170
    # 0x0005: inherited                                                               # Scenes 1.4 p.30 - no writable
    # 0x0009: inherited                                                               # Alarms - not described until now
    0x0204: [0,1,2],                                                                  # Thermostat User Interface Configuration p. 205
    # 0x0405: inherited                                                               # Relativ Humidity Measurement, 2.6 p. 103
    # 0x0402: inherited                                                               # Temperature Measurement, 2.3 p. 97
  })
  
  # Cluster 0x201 - Thermostat
  var shadow_current_temperature                    # Last known LocalTem­perature (0x0000) 
  var shadow_abs_min_heat_setpoint_limit            # Last known AbsMinHeat­Set­pointLimit (0x0003)
  var shadow_abs_max_heat_setpoint_limit            # Last known AbsMaxHeat­Set­pointLimit (0x0004)
  var shadow_abs_min_cool_setpoint_limit            # Last known AbsMinHeat­Set­pointLimit (0x0005)
  var shadow_abs_max_cool_setpoint_limit            # Last known AbsMaxHeat­Set­pointLimit (0x0006)
  var shadow_target_temp_cool                       # Last known Occupied­Cool­ingSet­point (0x0011)
  var shadow_target_temp_heat                       # Last known OccupiedHeat­ingSet­point (0x0012)
  var shadow_min_heat_setpoint_limit                # Last known MinHeat­Set­pointLimit (0x0015)
  var shadow_max_heat_setpoint_limit                # Last known MaxHeat­Set­pointLimit (0x0016)
  var shadow_min_cool_setpoint_limit                # Last known MinCoolSet­pointLimit (0x0017)
  var shadow_max_cool_setpoint_limit                # Last known MaxCool­Set­pointLimit (0x0018)
  var shadow_control_sequence                       # Last known ControlSe­quenceOf­Operation (0x001B)
  var shadow_system_mode                            # Last knwon System­Mode (0x001C)
  var shadow_thermostat_running_mode                # Last known Ther­mosta­tRunning­Mode (0x001E)
  var shadow_feature_map                            # Last known FeatureMap (0xFFFC)
  
  # Cluster 0x204 - Thermostat User Interface Configuration
  var shadow_temperature_display_mode               # Last known Tempera­tureDis­playMode (0x0000)
  var shadow_child_lock                             # Last known Keypad­Lockout (0x0001)
  var shadow_schedule_programming_visible           # Last known Sched­ulePro­gram­mingVisi­bility (0x0002)

  #############################################################
  # Constructor
  def init(device, endpoint, arguments)
    print (self.DISPLAY_NAME, "init(", str(device), ",", str(endpoint),",",str(arguments),")")
    super(self).init(device, endpoint, arguments)
    
    # Init Cluster 0x201 attributes
    self.shadow_feature_map = 0x01                  # Heating only
    
    self.shadow_current_temperature = nil           # default = null
    
    self.shadow_abs_min_heat_setpoint_limit = 700   # default = 7°C
    self.shadow_abs_max_heat_setpoint_limit = 3000  # default = 30°C
    self.shadow_abs_min_cool_setpoint_limit = 1600  # default = 16°C
    self.shadow_abs_max_cool_setpoint_limit = 3200  # default = 32°C

    self.shadow_target_temp_cool = 2600             # default = 26°C
    self.shadow_target_temp_heat = 2000             # default = 20°C
    
    self.shadow_min_heat_setpoint_limit = self.shadow_abs_min_heat_setpoint_limit # default = AbsMinHeatSetpointLimit
    self.shadow_max_heat_setpoint_limit = self.shadow_abs_max_heat_setpoint_limit # default = AbsMaxHeatSetpointLimit
    self.shadow_min_cool_setpoint_limit = self.shadow_abs_min_cool_setpoint_limit # default = AbsMinCoolSetpointLimit
    self.shadow_max_cool_setpoint_limit = self.shadow_abs_max_cool_setpoint_limit # default = AbsMaxCoolSetpointLimit

    self.shadow_control_sequence = 4                # default = 4 = HeatingAndCooling
    self.shadow_system_mode = 1                     # default = 1 = Auto

    self.shadow_thermostat_running_mode = 0         # default = 0 = Off

    # Intit Cluster 0x204 attributes
    self.shadow_temperature_display_mode = 0        # default = 0 = °C
    self.shadow_child_lock = 0                      # default = 0 = All functions available
    self.shadow_schedule_programming_visible = 0    # default = 0 = Local schedule pro­gramming functionality is enabled at the ther­mostat
  end

  #############################################################
  # read an attribute
  #
  def read_attribute(session, ctx, tlv_solo)
    import string
    print(self.DISPLAY_NAME, "read_attribute(",string.hex(ctx.cluster), string.hex(ctx.attribute),")")
    var TLV = matter.TLV
    var cluster = ctx.cluster
    var attribute = ctx.attribute

    # ====================================================================================================
    if cluster == 0x0201              # ========== Thermostat ==========
      if attribute == 0x0000                #  ---------- LocalTem­perature / i16 (*100) ----------
        if self.shadow_current_temperature != nil
          return tlv_solo.set(TLV.I2, self.shadow_current_temperature)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0003              #  ---------- AbsMin­HeatSet­pointLimit / i16 (*100) ----------
        if self.shadow_abs_min_heat_setpoint_limit != nil
          return tlv_solo.set(TLV.I2, self.shadow_abs_min_heat_setpoint_limit)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0004              #  ---------- AbsMax­HeatSet­pointLimit / i16 (*100) ----------
        if self.shadow_abs_max_heat_setpoint_limit != nil
          return tlv_solo.set(TLV.I2, self.shadow_abs_max_heat_setpoint_limit)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0005              #  ---------- AbsMin­CoolSet­pointLimit / i16 (*100) ----------
        if self.shadow_abs_min_cool_setpoint_limit != nil
          return tlv_solo.set(TLV.I2, self.shadow_abs_min_cool_setpoint_limit)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0006              #  ---------- AbsMax­CoolSet­pointLimit / i16 (*100) ----------
        if self.shadow_abs_max_cool_setpoint_limit != nil
          return tlv_solo.set(TLV.I2, self.shadow_abs_max_cool_setpoint_limit)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0011              #  ---------- Occu­piedCoolingSet­point / i16 (*100) ----------
        if self.shadow_target_temp_cool != nil
          return tlv_solo.set(TLV.I2, self.shadow_target_temp_cool)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0012              #  ---------- Occu­piedHeat­ingSet­point / i16 (*100) ----------
        if self.shadow_target_temp_heat != nil
          return tlv_solo.set(TLV.I2, self.shadow_target_temp_heat)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0015              #  ---------- MinHeat­Set­pointLimit / i16 (*100) ----------
        if self.shadow_min_heat_setpoint_limit != nil
          return tlv_solo.set(TLV.I2, self.shadow_min_heat_setpoint_limit)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0016              #  ---------- MaxHeat­Set­pointLimit / i16 (*100) ----------
        if self.shadow_max_heat_setpoint_limit != nil
          return tlv_solo.set(TLV.I2, self.shadow_max_heat_setpoint_limit)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0017              #  ---------- MinCool­Set­pointLimit / i16 (*100) ----------
        if self.shadow_min_cool_setpoint_limit != nil
          return tlv_solo.set(TLV.I2, self.shadow_min_cool_setpoint_limit)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0018              #  ---------- MaxCool­Set­pointLimit / i16 (*100) ----------
        if self.shadow_max_cool_setpoint_limit != nil
          return tlv_solo.set(TLV.I2, self.shadow_max_cool_setpoint_limit)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x001B              # ---------- ControlSe­quenceOf­Operation ----------
        if self.shadow_control_sequence != nil
          return tlv_solo.set(TLV.U1, self.shadow_control_sequence)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x001C              # ---------- SystemMode ----------
        if self.shadow_system_mode != nil
          return tlv_solo.set(TLV.U1, self.shadow_system_mode)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x001E              # ---------- Ther­mosta­tRunning­Mode ----------
        if self.shadow_thermostat_running_mode != nil
          return tlv_solo.set(TLV.U1, self.shadow_thermostat_running_mode)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      # ---------------- Feature Map and ClusterRevision ---------------- #
      elif attribute == 0xFFFC              #  ---------- FeatureMap / map32 ----------
        if self.shadow_feature_map != nil
          return tlv_solo.set(TLV.U4, self.shadow_feature_map)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0xFFFD              #  ---------- ClusterRevision / u2 ----------
        return tlv_solo.set(TLV.U4, 6)      # 6 = See matter 1.1 spec
      end
    
    elif cluster == 0x0204        # ========== Thermostat User Interface Configuration ==========
      if attribute == 0x0000            #  ---------- Tempera­tureDis­playMode ----------
        if self.shadow_temperature_display_mode != nil
          return tlv_solo.set(TLV.U1, self.shadow_temperature_display_mode)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0001            #  ---------- Keypad­Lockout ----------
        if self.shadow_child_lock != nil
          return tlv_solo.set(TLV.U1, self.shadow_child_lock)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      elif attribute == 0x0002            #  ---------- Sched­ulePro­gram­mingVisi­bility ----------
        if self.shadow_schedule_programming_visible != nil
          return tlv_solo.set(TLV.U1, self.shadow_schedule_programming_visible)
        else
          return tlv_solo.set(TLV.NULL, nil)
        end
      end
    else
      return super(self).read_attribute(session, ctx, tlv_solo)
    end
    
  end

end
matter.Plugin_Thermostat = Matter_Plugin_Thermostat
