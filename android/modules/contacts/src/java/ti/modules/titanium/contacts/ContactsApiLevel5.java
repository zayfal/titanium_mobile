package ti.modules.titanium.contacts;

import java.io.IOException;
import java.io.InputStream;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.titanium.TiApplication;
import org.appcelerator.titanium.TiC;
import org.appcelerator.titanium.TiContext;
import org.appcelerator.titanium.util.TiConvert;

import android.app.Activity;
import android.content.ContentProviderOperation;
import android.content.ContentProviderResult;
import android.content.ContentResolver;
import android.content.ContentUris;
import android.content.Intent;
import android.content.OperationApplicationException;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.RemoteException;
import android.provider.ContactsContract;
import android.provider.ContactsContract.CommonDataKinds.Event;
import android.provider.ContactsContract.CommonDataKinds.Phone;
import android.provider.ContactsContract.CommonDataKinds.StructuredName;
import android.provider.ContactsContract.CommonDataKinds.StructuredPostal;
import android.provider.ContactsContract.Data;
import android.provider.ContactsContract.RawContacts;
import android.util.Log;

public class ContactsApiLevel5 extends CommonContactsApi
{
	protected boolean loadedOk;
	//private WeakReference<TiContext> weakContext ;
	private static final String LCAT = "TiContacts5";
	private Method openContactPhotoInputStream;
	private static Class<?> Contacts;
	private static Uri ContactsUri;
	private static Uri DataUri;
	private static String[] DATA_PROJECTION = new String[] {
		"contact_id",
		"mimetype",
		"photo_id",
		"display_name",
		"data1",
		"data2",
		"data3",
		"data4",
		"data5",
		"data6",
		"data7",
		"data8",
		"data9",
		"data10"
		
	};
	protected static int DATA_COLUMN_CONTACT_ID = 0;
	protected static int DATA_COLUMN_MIMETYPE = 1;
	protected static int DATA_COLUMN_PHOTO_ID = 2;
	protected static int DATA_COLUMN_DISPLAY_NAME = 3;
	protected static int DATA_COLUMN_DATA1 = 4;
	protected static int DATA_COLUMN_DATA2 = 5;
	protected static int DATA_COLUMN_DATA3 = 6;
	protected static int DATA_COLUMN_DATA4 = 7;
	protected static int DATA_COLUMN_DATA5 = 8;
	protected static int DATA_COLUMN_DATA6 = 9;
	protected static int DATA_COLUMN_DATA7 = 10;
	protected static int DATA_COLUMN_DATA8 = 11;
	protected static int DATA_COLUMN_DATA9 = 12;
	protected static int DATA_COLUMN_DATA10 = 13;
	
	protected static int DATA_COLUMN_NOTE = DATA_COLUMN_DATA1;
	
	protected static int DATA_COLUMN_EMAIL_ADDR = DATA_COLUMN_DATA1;
	protected static int DATA_COLUMN_EMAIL_TYPE = DATA_COLUMN_DATA2;
	
	protected static int DATA_COLUMN_PHONE_NUMBER = DATA_COLUMN_DATA1;
	protected static int DATA_COLUMN_PHONE_TYPE = DATA_COLUMN_DATA2;
	
	protected static int DATA_COLUMN_NAME_FIRST = DATA_COLUMN_DATA2;
	protected static int DATA_COLUMN_NAME_LAST = DATA_COLUMN_DATA3;
	protected static int DATA_COLUMN_NAME_PREFIX = DATA_COLUMN_DATA4;
	protected static int DATA_COLUMN_NAME_MIDDLE = DATA_COLUMN_DATA5;
	protected static int DATA_COLUMN_NAME_SUFFIX = DATA_COLUMN_DATA6;
	
	protected static int DATA_COLUMN_ADDRESS_FULL = DATA_COLUMN_DATA1;
	protected static int DATA_COLUMN_ADDRESS_TYPE = DATA_COLUMN_DATA2;
	protected static int DATA_COLUMN_ADDRESS_STREET = DATA_COLUMN_DATA4;
	protected static int DATA_COLUMN_ADDRESS_POBOX = DATA_COLUMN_DATA5;
	protected static int DATA_COLUMN_ADDRESS_NEIGHBORHOOD = DATA_COLUMN_DATA6;
	protected static int DATA_COLUMN_ADDRESS_CITY = DATA_COLUMN_DATA7;
	protected static int DATA_COLUMN_ADDRESS_STATE = DATA_COLUMN_DATA8;
	protected static int DATA_COLUMN_ADDRESS_POSTCODE = DATA_COLUMN_DATA9;
	protected static int DATA_COLUMN_ADDRESS_COUNTRY = DATA_COLUMN_DATA10;
	
	protected static String KIND_NAME = "vnd.android.cursor.item/name";
	protected static String KIND_EMAIL = "vnd.android.cursor.item/email_v2";
	protected static String KIND_NOTE = "vnd.android.cursor.item/note";
	protected static String KIND_PHONE = "vnd.android.cursor.item/phone_v2";
	protected static String KIND_ADDRESS = "vnd.android.cursor.item/postal-address_v2";
	
	
	private static String[] PEOPLE_PROJECTION = new String[] {
        "_id",
        "display_name",
        "photo_id"
    };
	protected static int PEOPLE_COL_ID = 0;
	protected static int PEOPLE_COL_NAME = 1;
	protected static int PEOPLE_COL_PHOTO_ID = 2;
	
	private static String INConditionForKinds =
		"('" + KIND_ADDRESS + "','" + KIND_EMAIL + "','" +
		KIND_NAME + "','" + KIND_NOTE + "','" + KIND_PHONE + "')";
	
	protected ContactsApiLevel5()
	{
		//weakContext = new WeakReference<TiContext>(tiContext);
		loadedOk = true;
		try {
			DataUri = (Uri) Class.forName("android.provider.ContactsContract$Data").getField("CONTENT_URI").get(null);
			Contacts = Class.forName("android.provider.ContactsContract$Contacts");
			ContactsUri = (Uri) Contacts.getField("CONTENT_URI").get(null);
			openContactPhotoInputStream = Contacts.getMethod("openContactPhotoInputStream", ContentResolver.class, Uri.class);
			
		} catch (Throwable t) {
			Log.d(LCAT, "Failed to load ContactsContract$Contacts " + t.getMessage(),t);
			loadedOk = false;
			return;
		}
	}

	protected ContactsApiLevel5(TiContext tiContext)
	{
		this();
	}
	
	@Override
	protected PersonProxy[] getAllPeople(int limit)
	{
		return getPeople(limit, null, null);
	}
	
	private PersonProxy[] getPeople(int limit, String additionalCondition, String[] additionalSelectionArgs)
	{
		//TiContext tiContext = weakContext.get();
		/*if (tiContext == null) {
			Log.d(LCAT , "Could not getPeople, context is GC'd");
			return null;
		}*/
		
		if (TiApplication.getInstance() == null) {
			Log.e(LCAT, "Could not getPeople, application is null");
			return null;
		}
		
		Activity activity = TiApplication.getInstance().getRootOrCurrentActivity();
		if (activity == null) {
			Log.e(LCAT, "Could not getPeople, activity is null");
			return null;
		}
		
		LinkedHashMap<Long, CommonContactsApi.LightPerson> persons = new LinkedHashMap<Long, LightPerson>();
		
		String condition = "mimetype IN " + INConditionForKinds +
		" AND in_visible_group=1";
		
		if (additionalCondition != null) {
			condition += " AND " + additionalCondition;
		}
		
		Cursor cursor = activity.managedQuery(
				DataUri, 
				DATA_PROJECTION, 
				condition, 
				additionalSelectionArgs, 
				"display_name COLLATE LOCALIZED asc, contact_id asc, mimetype asc, is_super_primary desc, is_primary desc");
		
		while (cursor.moveToNext() && persons.size() < limit) {
			long id = cursor.getLong(DATA_COLUMN_CONTACT_ID);
			CommonContactsApi.LightPerson person;
			if (persons.containsKey(id)) {
				person = persons.get(id);
			} else {
				person = new CommonContactsApi.LightPerson();
				person.addPersonInfoFromL5DataRow(cursor);
				persons.put(id, person);
			}
			person.addDataFromL5Cursor(cursor);
		}
		
		cursor.close();
		
		return proxifyPeople(persons);
	}
	
	@Override
	protected Intent getIntentForContactsPicker()
	{
		return new Intent(Intent.ACTION_PICK, ContactsUri);
	}

	@Override
	protected PersonProxy[] getPeopleWithName(String name)
	{
		return getPeople(Integer.MAX_VALUE, "display_name like ? or display_name like ?" , new String[]{name + '%', "% " + name + '%'});
	}

	protected void updateContactField (ArrayList<ContentProviderOperation> ops, int insertIndex, String mimeType, String idKey,
			String idValue, String typeKey, int typeValue) 
	{
		if (typeKey == null) {
			ops.add(ContentProviderOperation
					.newInsert(Data.CONTENT_URI)
					.withValueBackReference(Data.RAW_CONTACT_ID, insertIndex)
					.withValue(Data.MIMETYPE, mimeType)
					.withValue(idKey, idValue) 
					.build());
		} else {
			ops.add(ContentProviderOperation
					.newInsert(Data.CONTENT_URI)
					.withValueBackReference(Data.RAW_CONTACT_ID, insertIndex)
					.withValue(Data.MIMETYPE, mimeType)
					.withValue(idKey, idValue) 
					.withValue(typeKey, typeValue)
					.build());
		}
	}
	
	protected void processAddress(HashMap addressHashMap, String addressType, ArrayList<ContentProviderOperation> ops, int insertIndex, int aType)
	{
		Object type = addressHashMap.get(addressType);
		if (type instanceof Object[]) {
			Object[] typeArray = (Object[]) type;
			for (int i = 0; i < typeArray.length; i++) {
				Object typeAddress = typeArray[i];
				if (typeAddress instanceof HashMap) {
					HashMap typeHashMap = (HashMap) typeAddress;
					if (typeHashMap.containsKey("CountryCode")) {
						String countryCode = TiConvert.toString(typeHashMap, "CountryCode");
						updateContactField(ops, insertIndex, StructuredPostal.CONTENT_ITEM_TYPE, StructuredPostal.COUNTRY, countryCode, StructuredPostal.TYPE, aType);
					}

					if (typeHashMap.containsKey("Street")) {
						String street = TiConvert.toString(typeHashMap, "Street");
						updateContactField(ops, insertIndex, StructuredPostal.CONTENT_ITEM_TYPE, StructuredPostal.STREET, street, StructuredPostal.TYPE, aType);
					}

					if (typeHashMap.containsKey("City")) {
						String city = TiConvert.toString(typeHashMap, "City");
						updateContactField(ops, insertIndex, StructuredPostal.CONTENT_ITEM_TYPE, StructuredPostal.CITY, city, StructuredPostal.TYPE, aType);
					}
					
					if (typeHashMap.containsKey("ZIP")) {
						String zip = TiConvert.toString(typeHashMap, "ZIP");
						updateContactField(ops, insertIndex, StructuredPostal.CONTENT_ITEM_TYPE, StructuredPostal.POSTCODE, zip, StructuredPostal.TYPE, aType);
					}
					
					if (typeHashMap.containsKey("State")) {
						String state = TiConvert.toString(typeHashMap, "State");
						updateContactField(ops, insertIndex, StructuredPostal.CONTENT_ITEM_TYPE, StructuredPostal.REGION, state, StructuredPostal.TYPE, aType);
					}
				}
			}
		}
	}
	
	protected void addContact(KrollDict options) {
		
		String firstName = "", lastName = "", fullName = "", middleName = "", displayName = "";
		String mobilePhone = "", workPhone = "";
		String birthday = "";
		PersonProxy newContact = new PersonProxy();
		ArrayList<ContentProviderOperation> ops = new ArrayList<ContentProviderOperation>();
		int insertIndex = ops.size();
		
		ops.add(ContentProviderOperation.newInsert(RawContacts.CONTENT_URI)
				.withValue(RawContacts.ACCOUNT_TYPE, null)
				.withValue(RawContacts.ACCOUNT_NAME, null).build());
		
		if (options.containsKey(TiC.PROPERTY_FIRSTNAME)) {
			firstName = TiConvert.toString(options, TiC.PROPERTY_FIRSTNAME);
			newContact.setProperty(TiC.PROPERTY_FIRSTNAME, firstName);
		}
		
		if (options.containsKey(TiC.PROPERTY_LASTNAME)) {
			lastName = TiConvert.toString(options, TiC.PROPERTY_LASTNAME);
			newContact.setProperty(TiC.PROPERTY_LASTNAME, lastName);
		}
		
		if (options.containsKey(TiC.PROPERTY_MIDDLENAME)) {
			middleName = TiConvert.toString(options, TiC.PROPERTY_MIDDLENAME);
			newContact.setProperty(TiC.PROPERTY_MIDDLENAME, middleName);
		}
		
		if (options.containsKey(TiC.PROPERTY_FULLNAME)) {
			fullName = TiConvert.toString(options, TiC.PROPERTY_FULLNAME);
			displayName = fullName;
		} else {
			displayName = firstName + " " + middleName + " " + lastName;
		}

		updateContactField(ops, insertIndex, StructuredName.CONTENT_ITEM_TYPE, StructuredName.DISPLAY_NAME, displayName, null, 0);
		newContact.setProperty(TiC.PROPERTY_FULLNAME, fullName);
		
		if (options.containsKey(TiC.PROPERTY_PHONE)) {
			Object phoneNumbers = options.get(TiC.PROPERTY_PHONE);
			if (phoneNumbers instanceof HashMap) {
				HashMap phones = (HashMap)phoneNumbers;
				newContact.setProperty(TiC.PROPERTY_PHONE, phones);
				
				if (phones.containsKey(TiC.PROPERTY_MOBILE)) {
					Object mobileArray = phones.get(TiC.PROPERTY_MOBILE);
					if (mobileArray instanceof Object[]) {
						Object[] tempArray = (Object[]) mobileArray;
						for (int i = 0; i < tempArray.length; i++) {
							mobilePhone = tempArray[i].toString();
							updateContactField(ops, insertIndex, Phone.CONTENT_ITEM_TYPE, Phone.NUMBER, mobilePhone, Phone.TYPE, Phone.TYPE_MOBILE);
						}
					}
				}
				
				if (phones.containsKey(TiC.PROPERTY_WORK)) {
					Object workArray = phones.get(TiC.PROPERTY_WORK);
					if (workArray instanceof Object[]) {
						Object[] tempArray = (Object[]) workArray;
						for (int i = 0; i < tempArray.length; i++) {
							workPhone = tempArray[i].toString();
							updateContactField(ops, insertIndex, Phone.CONTENT_ITEM_TYPE, Phone.NUMBER, workPhone, Phone.TYPE, Phone.TYPE_WORK);
						}
					}
				}
			}
		}
		
		if (options.containsKey(TiC.PROPERTY_BIRTHDAY)) {
			birthday = TiConvert.toString(options, TiC.PROPERTY_BIRTHDAY);
			newContact.setProperty(TiC.PROPERTY_BIRTHDAY, birthday);
			updateContactField(ops, insertIndex, Event.CONTENT_ITEM_TYPE, Event.START_DATE, birthday, Event.TYPE, Event.TYPE_BIRTHDAY);
		}
		
		if (options.containsKey(TiC.PROPERTY_ADDRESS)) {
			Object address = options.get(TiC.PROPERTY_ADDRESS);
			if (address instanceof HashMap) {
				HashMap addressHashMap = (HashMap) address;
				newContact.setProperty(TiC.PROPERTY_ADDRESS, addressHashMap);
				if (addressHashMap.containsKey(TiC.PROPERTY_WORK)) {
					processAddress(addressHashMap, TiC.PROPERTY_WORK, ops, insertIndex, StructuredPostal.TYPE_WORK);
				}
				
				if (addressHashMap.containsKey(TiC.PROPERTY_HOME)) {
					processAddress(addressHashMap, TiC.PROPERTY_HOME, ops, insertIndex, StructuredPostal.TYPE_HOME);
				}
			}
		}
		
		
		
		
		                 
		try
		{
			ContentProviderResult[] res = TiApplication.getAppRootOrCurrentActivity().getContentResolver().applyBatch(ContactsContract.AUTHORITY, ops);
		}
		catch (RemoteException e)
		{ 
			// error
		}
		catch (OperationApplicationException e) 
		{
			// error
		}       
	}
	
	@Override
	protected PersonProxy getPersonById(long id)
	{
		/*
		TiContext tiContext = weakContext.get();
		if (tiContext == null) {
			Log.d(LCAT , "Could not getPersonById, context is GC'd");
			return null;
		}
		*/
		
		if (TiApplication.getInstance() == null) {
			Log.e(LCAT, "Could not getPersonById, application is null");
			return null;
		}
		
		Activity activity = TiApplication.getInstance().getRootOrCurrentActivity();
		if (activity == null) {
			Log.e(LCAT, "Could not getPersonById, activity is null");
			return null;
		}
		
		CommonContactsApi.LightPerson person = null;
		
		// Basic person data.
		Cursor cursor = activity.managedQuery(
				ContentUris.withAppendedId(ContactsUri, id),
				PEOPLE_PROJECTION, null, null, null);
		
		if (cursor.moveToFirst()) {
			person = new CommonContactsApi.LightPerson();
			person.addPersonInfoFromL5PersonRow(cursor);
		}
		
		cursor.close();
		
		if (person == null) {
			return null;
		}
		
		// Extended data (emails, phones, etc.)
		String condition = "mimetype IN " + INConditionForKinds +
			" AND contact_id = ?";
		
		cursor = activity.managedQuery(
				DataUri, 
				DATA_PROJECTION, 
				condition, 
				new String[]{String.valueOf(id)}, 
				"mimetype asc, is_super_primary desc, is_primary desc");
		
		while (cursor.moveToNext()) {
			person.addDataFromL5Cursor(cursor);
		}
		cursor.close();
		return person.proxify();
	}

	@Override
	protected PersonProxy getPersonByUri(Uri uri)
	{
		long id = ContentUris.parseId(uri);
		return getPersonById(id);
	}

	@Override
	protected Bitmap getInternalContactImage(long id)
	{
		/*
		TiContext tiContext = weakContext.get();
		if (tiContext == null) {
			Log.d(LCAT , "Could not getContactImage, context is GC'd");
			return null;
		}
		*/
		
		if (TiApplication.getInstance() == null) {
			Log.e(LCAT, "Could not getInternalContactImage, application is null");
			return null;
		}
		
		Uri uri = ContentUris.withAppendedId(ContactsUri, id);
		ContentResolver cr = TiApplication.getInstance().getContentResolver();
		InputStream stream = null;
		try {
			stream = (InputStream) openContactPhotoInputStream.invoke(null, cr, uri);
		} catch (Throwable t) {
			Log.d(LCAT, "Could not invoke openContactPhotoInputStream: " + t.getMessage(), t);
			return null;
		}
		if (stream == null) {
			return null;
		}
		Bitmap bm = BitmapFactory.decodeStream(stream);
		try {
			stream.close();
		} catch (IOException e) {
			Log.d(LCAT, "Unable to close stream from openContactPhotoInputStream: " + e.getMessage(), e);
		}
		return bm;
	}
}
