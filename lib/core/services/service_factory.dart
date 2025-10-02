class ServiceFactory<T extends Object> {
  final T Function() _factoryMethod;

  ServiceFactory(this._factoryMethod);

  T create() => _factoryMethod();
}
