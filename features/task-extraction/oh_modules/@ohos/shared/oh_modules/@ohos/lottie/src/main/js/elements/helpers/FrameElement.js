/**
 * @file
 * Handles element's layer frame update.
 * Checks layer in point and out point
 *
 */

function FrameElement() {}

FrameElement.prototype = {
  /**
     * @function
     * Initializes frame related properties.
     *
     */
  initFrame: function () {
    // set to true when inpoint is rendered
    this._isFirstFrame = false;
    // list of animated properties
    this.dynamicProperties = [];
    // If layer has been modified in current tick this will be true
    this._mdf = false;
  },
  /**
     * @function
     * Calculates all dynamic values
     *
     * @param {number} num
     * current frame number in Layer's time
     * @param {boolean} isVisible
     * if layers is currently in range
     *
     */
  prepareProperties: function (num, isVisible) {
    var i;
    var len = this.dynamicProperties?.length;
    var canGetValue = false;
    for (i = 0; i < len; i += 1) {
      var property = this.dynamicProperties[i];
      // 检查 property 和 getValue
      canGetValue = property && typeof property.getValue === 'function';
      var shouldGetValue = canGetValue && (isVisible || (this._isParent && property.propType === 'transform'));

      if (shouldGetValue) {
        property.getValue();
        if (property._mdf) {
          this.globalData._mdf = true;
          this._mdf = true;
        }
      }
    }
  },
  addDynamicProperty: function (prop) {
    this.dynamicProperties = this.dynamicProperties || [];
    if (this.dynamicProperties.indexOf(prop) === -1) {
      this.dynamicProperties.push(prop);
    }
  },
};

export default FrameElement;
