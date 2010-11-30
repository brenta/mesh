package mesh
{
	import collections.ArraySet;
	import collections.HashMap;
	import collections.Set;
	
	import flash.utils.Proxy;
	import flash.utils.describeType;
	import flash.utils.flash_proxy;
	import flash.utils.getDefinitionByName;
	
	import validations.ValidationError;
	import validations.Validator;
	
	import reflection.clazz;
	import reflection.newInstance;

	/**
	 * An entity.
	 * 
	 * @author Dan Schultz
	 */
	public dynamic class Entity extends Proxy
	{
		private static const DESCRIPTIONS:HashMap = new HashMap();
		
		/**
		 * Constructor.
		 */
		public function Entity()
		{
			super();
			
			if (!DESCRIPTIONS.containsKey(clazz)) {
				DESCRIPTIONS.put(clazz, EntityDescription.fromEntity(clazz));
			}
		}
		
		/**
		 * Checks if two entities are equal.  By default, two entities are equal
		 * when they are of the same type, and their ID's are the same.
		 * 
		 * @param entity The entity to check.
		 * @return <code>true</code> if the entities are equal.
		 */
		public function equals(entity:Entity):Boolean
		{
			return entity != null && id.equals(entity.id);
		}
		
		/**
		 * Returns a generated hash value for this entity.  Two entities that represent
		 * the same data should return the same hash code.
		 * 
		 * @return A hash value.
		 */
		public function hashCode():Object
		{
			return id.guid;
		}
		
		/**
		 * Runs the validations defined for this entity and returns <code>true</code> if any
		 * validations failed.
		 * 
		 * @return <code>true</code> if any validations failed.
		 * 
		 * @see #isValid()
		 * @see #validate()
		 */
		final public function isInvalid():Boolean
		{
			return !isValid();
		}
		
		/**
		 * Runs the validations defined for this entity and returns <code>true</code> if all
		 * validations passed.
		 * 
		 * @return <code>true</code> if all validations passed.
		 * 
		 * @see #isInvalid()
		 * @see #validate()
		 */
		final public function isValid():Boolean
		{
			return validate().length == 0;
		}
		
		/**
		 * Marks this entity as dirty.
		 */
		public function modified():void
		{
			_isDirty = true;
		}
		
		/**
		 * Marks this entity as being persisted.
		 */
		public function saved():void
		{
			_isDirty = false;
		}
		
		/**
		 * Runs the validations defined on this entity and returns the set of errors for
		 * any validations that failed. If all validations passed, this method returns an
		 * empty array.
		 *
		 * @return A set of <code>ValidationError</code>s.
		 * 
		 * @see #isInvalid()
		 * @see #isValid()
		 */
		public function validate():Array
		{
			var errors:Array = [];
			for each (var validator:Validator in validators()) {
				var error:Object = validator.validate(this);
				if (error) {
					errors.push(error);
				}
			}
			return errors;
		}
		
		/**
		 * Returns a set of validators defined for this entity. This method allows sub-classes
		 * to override and supply their own validators without using metadata. The default
		 * implementation of this method will return any validators that were defined in metadata.
		 * 
		 * @return A set of <code>Validator</code>s.
		 */
		protected function validators():Array
		{
			var descriptionXML:XML = describeType(this);
			var validators:Array = [];
			
			for each (var validateXML:XML in descriptionXML..metadata.(@name == "Validate")) {
				var property:String = validateXML.arg.(@key == "property").@value;
				
				if (validateXML.parent().name == "accessor") {
					property = validateXML.parent().name;
				}
				
				var validator:Object = newInstance(getDefinitionByName(validateXML.arg.(@key == "validator").@value) as Class);
				for each (var argXML:XML in validateXML..arg) {
					if (argXML.@key != "property" || argXML.@key != "validator") {
						validator[argXML.@key] = argXML.@value;
					}
				}
				
				validators.push(validator);
			}
			
			return validators;
		}
		
		/**
		 * The class for this entity.
		 */
		public function get clazz():Class
		{
			return reflection.clazz(this);
		}
		
		private var _id:EntityID = new EntityID();
		/**
		 * An object that represents the ID for this entity.
		 */
		public function get id():EntityID
		{
			return _id;
		}
		
		private var _isDirty:Boolean;
		/**
		 * <code>true</code> if this entity is dirty and needs to be persisted.
		 */
		public function get isDirty():Boolean
		{
			return _isDirty;
		}
		
		/**
		 * Returns the set of <code>Aggregate</code>s for this entity.
		 */
		public function get aggregates():Set
		{
			return DESCRIPTIONS.grab(clazz).aggregates;
		}
		
		/**
		 * Returns the set of <code>Relationship</code>s for this entity.
		 */
		public function get relationships():Set
		{
			return DESCRIPTIONS.grab(clazz).relationships;
		}
		
		private var _valueObjects:Object = {};
		
		/**
		 * @private
		 */
		override flash_proxy function getProperty(name:*):*
		{
			name = getNameFromQName(name);
			
			if (_valueObjects.hasOwnProperty(name)) {
				return _valueObjects[name];
			}
			
			for each (var aggregate:Aggregate in aggregates) {
				if (aggregate.hasMappedProperty(name)) {
					return aggregate.getValue(this, name);
				}
			}
			
			return undefined;
		}
		
		/**
		 * @private
		 */
		override flash_proxy function hasProperty(name:*):Boolean
		{
			return flash_proxy::getProperty(name) !== undefined;
		}
		
		/**
		 * @private
		 */
		override flash_proxy function setProperty(name:*, value:*):void
		{
			name = getNameFromQName(name);
			for each (var aggregate:Aggregate in aggregates) {
				if (aggregate.property == name) {
					_valueObjects[name] = value;
					return;
				}
				
				if (aggregate.hasMappedProperty(name)) {
					aggregate.setValue(this, name, value);
				}
			}
		}
		
		private function getNameFromQName(name:*):String
		{
			if (name is QName) {
				name = name.localName;
			}
			return name;
		}
	}
}