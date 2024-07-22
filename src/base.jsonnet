// Copyright (c) 2022-2024 Nomadic Labs <contact@nomadic-labs.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the "Software"),
// to deal in the Software without restriction, including without limitation
// the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.

local grafonnet = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';
local variableQuery = grafonnet.dashboard.variable.query;
local panel = grafonnet.panel;
local stat = panel.stat;
local table = panel.table;
local timeSeries = panel.timeSeries;
local query = grafonnet.query;

{

  // Parameters
  namespace: 'octez',

  node_instance: std.extVar('node_instance_label'),

  node_instance_query: '{' + self.node_instance + '="$node_instance"}',

  // Prometheus query
  prometheus(q, legendFormat=''):
    local withLegendFormat = if legendFormat != ''
    then query.prometheus.withLegendFormat(legendFormat) else {};
    grafonnet.query.prometheus.new('Prometheus', self.namespace + '_' + q + self.node_instance_query)
    + withLegendFormat,

  // Stat panel helpers
  info:
    {
      new(title, q, h, w, x, y, instant=true):
        local q0 = if instant then
          q + grafonnet.query.prometheus.withInstant(true)
        else q;
        stat.new(title)
        + stat.panelOptions.withGridPos(h, w, x, y)
        + stat.queryOptions.withTargets(q)
        + stat.options.withGraphMode('none')
        + stat.options.withColorMode('none'),

      withName():
        stat.options.withTextMode('name'),

      // [withThreshold(thresholds)] Returns the threshold object for stat panels.
      // [threshold] is a [value,color] list.
      withThreshold(thresholds):
        local f(t) =
          stat.standardOptions.threshold.step.withValue(t[0])
          + stat.standardOptions.threshold.step.withColor(t[1]);
        local threshold =
          std.map(f, thresholds);
        stat.standardOptions.thresholds.withMode('absolute')
        + stat.standardOptions.thresholds.withSteps(threshold),

      // [withMapping(mappings)] Returns the mapping object for stat panels.
      // [mapping] is a [value,text,color] list.
      withMapping(mappings):
        local unknown =
          stat.standardOptions.mapping.SpecialValueMap.options.withMatch('null')
          + stat.standardOptions.mapping.SpecialValueMap.options.result.withText('Unknown')
          + stat.standardOptions.mapping.SpecialValueMap.options.result.withColor('yellow');
        local f(t) =
          stat.standardOptions.mapping.RangeMap.withType()
          + stat.standardOptions.mapping.RangeMap.options.withFrom(t[0])
          + stat.standardOptions.mapping.RangeMap.options.withTo(t[0])
          + stat.standardOptions.mapping.RangeMap.options.result.withText(t[1])
          + stat.standardOptions.mapping.RangeMap.options.result.withColor(t[2]);
        local mapping =
          std.map(f, mappings);
        stat.options.withColorMode('value')
        + stat.standardOptions.withMappings(mapping + [unknown]),

    },

  // TimeSeries panel helpers
  graph:
    {
      new(title, q, h, w, x, y):
        timeSeries.new(title)
        + timeSeries.panelOptions.withGridPos(h, w, x, y)
        + timeSeries.fieldConfig.defaults.custom.withLineWidth(1)
        + timeSeries.queryOptions.withTargets(q),

      withLegend(calcs=[]):
        timeSeries.options.legend.withDisplayMode('table')
        + timeSeries.options.legend.withAsTable()
        + timeSeries.options.legend.withShowLegend()
        + timeSeries.options.legend.withCalcs(calcs),

      // Legends as a table placed to the bottom with [calcs] values.
      withLegendBottom(calcs=[]):
        self.withLegend(calcs)
        + timeSeries.options.legend.withPlacement('bottom'),

      // Legends as a table placed on the right side with [calcs] values.
      withLegendRight(calcs=[]):
        self.withLegend(calcs)
        + timeSeries.options.legend.withPlacement('right'),

      // Apply a fixed [color]
      withFixedColor(color):
        timeSeries.standardOptions.color.withMode('fixed')
        + timeSeries.standardOptions.color.withFixedColor(color),

      // [withQueryColor(colors)] Applies colors to queries.
      // [colors] is a [name,color] list.
      withQueryColor(colors):
        local f(t) =
          timeSeries.standardOptions.override.byName.new(t[0])
          + timeSeries.standardOptions.override.byName.withPropertiesFromOptions(
            self.withFixedColor(t[1])
          );
        local overrides = std.map(f, colors);
        timeSeries.standardOptions.withOverrides(overrides),

    },

  table(title, q, h, w, x, y):
    table.new(title)
    + table.panelOptions.withGridPos(h, w, x, y)
    + table.queryOptions.withTargets(q)
    + table.queryOptions.withTransformations([{
      id: 'seriesToRows',
      options: {},
    }])
    + table.standardOptions.withOverrides(
      [
        {
          matcher: {
            id: 'byName',
            options: 'Time',
          },
          properties: [
            {
              id: 'custom.hidden',
              value: 'true',
            },
          ],
        },
      ]
    ),

  // Variables
  nodeInstance:
    variableQuery.new(
      name='node_instance',
      query='label_values(octez_version,' + std.extVar('node_instance_label') + ')',
    )
    + variableQuery.generalOptions.withLabel('Node Instance')
    + variableQuery.refresh.onLoad()
    + variableQuery.withDatasource('prometheus', 'Prometheus'),

}
