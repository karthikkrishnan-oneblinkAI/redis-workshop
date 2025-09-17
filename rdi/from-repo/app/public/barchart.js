/**
 * Create an empty shell of a chart that bars can be added to
 */
function displayStackedChart(chartId) {
  // create an SVG element inside the div that fills 100% of the div
  const vis = d3
    .select("#" + chartId)
    .append("svg:svg")
    .attr("width", "100%")
    .attr("height", "100%")
    // transform down to simulate making the origin bottom-left instead of top-left
    // we will then need to always make Y values negative
    .append("g")
    .attr("class", "barChart")
    .attr("transform", "translate(0, " + chartHeight + ")");
}

/* the property names on the data objects that we'll get data from */
const propertyNames = ["a"];

/**
 * Add or update a bar of data in the given chart
 *
 * The data object expects to have an 'id' property to identify itself (id == a single bar)
 * and have object properties with numerical values for each property in the 'propertyNames' array.
 */
function addData(chartId, data) {
  // if data already exists for this data ID, update it instead of adding it
  const existingBarNode = document.querySelectorAll(
    "#" + chartId + "_" + data.id
  );
  if (existingBarNode.length > 0) {
    const existingBar = d3.select(existingBarNode.item(existingBarNode.length));
    // reset the decay since we received an update
    existingBar.transition().duration(100).attr("style", "opacity:1.0");
    // update the data on each data point defined by 'propertyNames'
    for (index in propertyNames) {
      existingBar
        .select("rect." + propertyNames[index])
        .transition()
        .ease("linear")
        .duration(300)
        .attr("y", barY(data, propertyNames[index]))
        .attr("height", barHeight(data, propertyNames[index]));
    }
  } else {
    // it's new data so add a bar
    const barDimensions = updateBarWidthsAndPlacement(chartId);

    // select the chart and add the new bar
    const barGroup = d3
      .select("#" + chartId)
      .selectAll("g.barChart")
      .append("g")
      .attr("class", "bar")
      .attr("id", chartId + "_" + data.id)
      .attr("style", "opacity:1.0");

    // now add each data point to the stack of this bar
    for (index in propertyNames) {
      barGroup
        .append("rect")
        .attr("class", propertyNames[index])
        .attr("width", barDimensions.barWidth - 1)
        .attr("x", function () {
          return (barDimensions.numBars - 1) * barDimensions.barWidth;
        })
        .attr("y", barY(data, propertyNames[index]))
        .attr("height", barHeight(data, propertyNames[index]));
    }

    // setup an interval timer for this bar that will decay the coloring
    barGroup.styleInterval = setInterval(function () {
      const theBar = document.getElementById(chartId + "_" + data.id);
      if (theBar === undefined) {
        clearInterval(barGroup.styleInterval);
      } else {
        if (theBar?.style.opacity > 0.2) {
          theBar.style.opacity = theBar.style.opacity - 0.05;
        }
      }
    }, 1000);
  }
}

/**
 * Remove a bar of data in the given chart
 *
 * The data object expects to have an 'id' property to identify itself (id == a single bar)
 * and have object properties with numerical values for each property in the 'propertyNames' array.
 */
function removeData(chartId) {
  const existingBarNode = $("g.bar"); //document.querySelectorAll("#" + chartId + "_" + barId);

  if (existingBarNode.length > 0 && existingBarNode.length >= 100) {
    // bar exists so we'll remove it
    const barGroup = d3.select(existingBarNode[0]);
    barGroup.transition().duration(200).remove();
  }
}

/**
 * Update the bar widths and x positions based on the number of bars.
 * @returns {barWidth: X, numBars:Y}
 */
function updateBarWidthsAndPlacement(chartId) {
  /**
   * Since we dynamically add/remove bars we can't use data indexes but must determine how
   * many bars we have already in the graph to calculate x-axis placement
   */
  const numBars =
    document.querySelectorAll("#" + chartId + " g.bar").length + 1;

  // determine what the width of all bars should be
  let barWidth = chartWidth / numBars;
  if (barWidth > 50) {
    barWidth = 50;
  }

  // reset the width and x position of each bar to fit
  const barNodes = document.querySelectorAll(
    "#" + chartId + " g.barChart g.bar"
  );
  for (var i = 0; i < barNodes.length; i++) {
    d3.select(barNodes.item(i))
      .selectAll("rect")
      //.transition().duration(10) // animation makes the display choppy, so leaving it out
      .attr("x", i * barWidth)
      .attr("width", barWidth - 1);
  }

  return { barWidth, numBars };
}

/*
 * Function to calculate the Y position of a bar
 */
function barY(data, propertyOfDataToDisplay) {
  /*
   * Determine the baseline by summing the previous values in the data array.
   * There may be a cleaner way of doing this with d3.layout.stack() but it
   * wasn't obvious how to do so while playing with it.
   */
  const baseline = 0;
  for (var j = 0; j < index; j++) {
    baseline = baseline + data[propertyNames[j]];
  }
  // make the y value negative 'height' instead of 0 due to origin moved to bottom-left
  return -y(baseline + data[propertyOfDataToDisplay]);
}

/*
 * Function to calculate height of a bar
 */
function barHeight(data, propertyOfDataToDisplay) {
  return data[propertyOfDataToDisplay];
}

// used to populate random data for testing
function randomInt(magnitude) {
  return Math.floor(Math.random() * magnitude);
}
