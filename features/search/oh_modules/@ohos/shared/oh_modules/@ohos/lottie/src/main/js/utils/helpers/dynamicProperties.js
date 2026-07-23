function DynamicPropertyContainer() {
  // 初始化默认属性，防止未调用 initDynamicPropertyContainer 时出错
  this.dynamicProperties = [];
  this.container = null;
  this._mdf = false;
  this._isAnimated = false;
}
DynamicPropertyContainer.prototype = {
  addDynamicProperty: function (prop) {
    // 检查 prop 是否有效
    if (!prop) {
      return;
    }

    // 确保 dynamicProperties 存在
    if (!Array.isArray(this.dynamicProperties)) {
      this.dynamicProperties = [];
    }

    // 检查是否已存在该属性
    if (this.dynamicProperties.indexOf(prop) === -1) {
      this.dynamicProperties.push(prop);

      // 检查 container 和 addDynamicProperty 方法是否存在
      if (this.container && typeof this.container.addDynamicProperty === 'function') {
        this.container.addDynamicProperty(this);
      }
      this._isAnimated = true;
    }
  },
  iterateDynamicProperties: function () {
    this._mdf = false;

    // 确保 dynamicProperties 存在且是数组
    if (!Array.isArray(this.dynamicProperties)) {
      this.dynamicProperties = [];
      return;
    }
    var i;
    var len = this.dynamicProperties.length;
    for (i = 0; i < len; i += 1) {
      var prop = this.dynamicProperties[i];
      // 检查 prop 和 getValue 方法是否存在
      if (prop && typeof prop.getValue === 'function') {
        prop.getValue();
        if (prop._mdf) {
          this._mdf = true;
        }
      }
    }
  },
  initDynamicPropertyContainer: function (container) {
    this.container = container;
    this.dynamicProperties = [];
    this._mdf = false;
    this._isAnimated = false;
  },
};

export default DynamicPropertyContainer;
