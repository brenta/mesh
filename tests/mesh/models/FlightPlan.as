package mesh.models
{
	import mesh.Entity;
	import mesh.adaptors.MockAdaptor;
	import mesh.adaptors.ServiceAdaptor;
	
	[HasOne(type="mesh.models.Airport", property="departing", lazy="false")]
	[HasOne(type="mesh.models.Airport", property="arriving", lazy="false")]
	[HasMany(type="mesh.models.NavigationAid", property="legs", lazy="false")]
	[HasMany(type="mesh.models.Airport", property="alternates", lazy="true")]
	
	public dynamic class FlightPlan extends Entity
	{
		[ServiceAdaptor]
		public static var adaptor:MockAdaptor;
		
		public function FlightPlan()
		{
			super();
		}
		
		override public function translateFrom(object:Object):void
		{
			var data:FlightPlanVO = FlightPlanVO( object );
			id = data.id;
			this.departing = NavigationAid.from(data.departing) as Airport;
			this.departing.translateFrom(data.departing);
			this.arriving = NavigationAid.from(data.arriving) as Airport;
			this.arriving.translateFrom(data.arriving);
			
			var legs:Array = [];
			for each (var waypoint:NavigationAidVO in data.legs) {
				var leg:NavigationAid = NavigationAid.from(waypoint);
				leg.translateFrom(waypoint);
				legs.push(leg);
			}
			this.legs.target = legs;
		}
		
		override public function translateTo():Object
		{
			var data:FlightPlanVO = new FlightPlanVO();
			data.id = id;
			data.arriving = this.arriving.translateTo() as AirportVO;
			data.departing = this.departing.translateTo() as AirportVO;
			
			data.legs = [];
			for each (var legs:NavigationAid in this.legs) {
				data.legs.push(legs.translateTo());
			}
			return data;
		}
	}
}