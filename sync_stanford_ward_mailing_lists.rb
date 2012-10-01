require 'rubygems'
#require 'fastercsv'

# mechanize 2.0 doesn't work
gem 'mechanize', '<2.0'
require 'mechanize'
require 'highline/import'
require 'optparse'
require 'logger'
require 'csv'

WHITE_LIST_URL = 'https://docs.google.com/spreadsheet/pub?hl=en_US&hl=en_US&key=0AgTd0uGWN6wQdFJvbmJPOVZwNEJfWnpmaDBwM2RZRkE&output=csv'
BLACK_LIST_URL = 'https://docs.google.com/spreadsheet/pub?hl=en_US&hl=en_US&key=0AgTd0uGWN6wQdFI0OVBPSUU1aEJMeF9xQl9ZaUVBY2c&output=csv'
STANFORD_2ND_WARD_LIST = 'stanford-2nd-ward'
STANFORD_2ND_WARD_LEADERSHIP_LIST = 'stanford-2nd-ward-leadership'
STANFORD_2ND_WARD_EQ_LIST = 'stanford-2nd-ward-eq'
STANFORD_2ND_WARD_RS_LIST = 'stanford-2nd-ward-rs'

LDS_LOGIN_URL = 'https://lds.org/SSOSignIn/'
LDS_CSV_URL = 'https://lds.org/directory/services/ludrs/unit/member-list/412031/csv'
GOOGLE_LOGIN_URL = 'https://www.google.com/accounts/ServiceLogin'
GOOGLE_GROUPS_URL = 'https://groups.google.com'
GOOGLE_GROUPS_INVITE = 'http://groups.google.com/group/%s/members_invite'

MESSAGE = 'Please accept this invitation to join the %s mailing list, used for official announcements and ward business.

To do so, simply follow the instructions in the "Google Groups Information" section below.

If you have already signed up under a different email address, please update your email address on lds.org.

Thank you'

class Member
  attr_accessor :lastname,:firstname,:email,:sex
  def initialize(new_lastname,new_firstname,new_email,new_sex)
    self.lastname = new_lastname
    self.firstname = new_firstname
    self.email = new_email
    self.sex = new_sex
  end
  def to_s
    puts "#{lastname}, #{firstname}, #{email}"
  end
end

def parse_options()
  options = {:invite => false}
  opts = OptionParser.new do |opts|
    opts.banner = "Usage: sync.rb [options]"

    opts.on('-g', '--googleusername USERNAME','Specify a username to use for Google') do |username|
      options[:google_username] = username
    end

    opts.on('-G', '--googlepassword PASSWORD','Specify a password to use for Google') do |password|
      options[:google_password] = password
    end

    opts.on('-l', '--ldsusername USERNAME','Specify a username to use for lds.org') do |username|
      options[:lds_username] = username
    end

    opts.on('-L', '--ldspassword PASSWORD','Specify a password to use for lds.org') do |password|
      options[:lds_password] = password
    end

    opts.on('-i', '--invite','Invite users to groups') do |invite|
      options[:invite] = true
    end

    opts.parse(ARGV)

    return options
  end
end

def invite(list,members)
  login_to_google(@google_username,@google_password)
  invite_page = @agent.get(GOOGLE_GROUPS_INVITE % list)
  invite_form = invite_page.form_with(:name => 'cr')
  invite_form.members_new = members.join(", ")
  invite_form.body = MESSAGE % list

  if @invite
    @agent.submit(invite_form,invite_form.buttons.first)
  else
    puts "Would have invited #{members}"
    puts "List: #{list}"
  end
  return members
end

def get_lds_members()
  login_page = @agent.get(LDS_LOGIN_URL)
  login_form = login_page.form_with(:id => 'loginForm')
  login_form.username = @lds_username
  login_form.password = @lds_password

  @agent.submit(login_form,login_form.buttons.first)

  csv = @agent.get(LDS_CSV_URL).body

  CSV.parse(csv, :headers => :first_row) do |row|
    email = row["Head Of House Email"]

    if email == "" or email == nil
      email = row["Family Email"]
    end

    email = email.downcase if email

    lastname, firstname = row["Head Of House Name"].split(", ")
    firstname = firstname.split()[0]
    sex = nil

    member = Member.new(lastname,firstname,email,sex)

    if email == "" or email == nil
      @no_emails << member
    else
      @emails[email] = member
      @lds_org_emails << email
    end
  end
end

def login_to_google(username,password)
  unless @google_logged_in
    google_page = @agent.get(GOOGLE_LOGIN_URL)
    login_form = google_page.form_with(:id => 'gaia_loginform')
    login_form.Email = username
    login_form.Passwd = password
    login_result = @agent.submit(login_form,login_form.buttons.first)
    puts login_result.body
    # should check if we are logged in somehow
    @google_logged_in = true
  end
end

def get_group_list(group,list)
  login_to_google(@google_username,@google_password)
  csv = @agent.get("https://groups.google.com/group/#{group}/manage_members/#{group}.csv?Action.Export=Export+member+list").body.split(/\n/)

  # We have to format the resulting text so that we can easily parse it. Get rid of the first line and then rejoin it
  csv.shift
  csv = csv.join("\n")

  CSV.parse(csv, :headers => :first_row) do |row|
    email = row["email address"].downcase
    list << email
  end
end

def get_s2_list(list)
  get_group_list(STANFORD_2ND_WARD_LIST,list)
end

def get_s2_eq_list(list)
  get_group_list(STANFORD_2ND_WARD_EQ_LIST,list)
end

def get_s2_rs_list(list)
  get_group_list(STANFORD_2ND_WARD_RS_LIST,list)
end

def get_google_list(url,list)
  csv = @agent.get(url).body
  CSV.parse(csv, :headers => :first_row) do |row|
    email = row["Email"]
    lastname = row["Lastname"]
    firstname = row["Firstname"]
    sex = nil

    @emails[email] = Member.new(lastname,firstname,email,sex)

    list << email
  end
end

def get_white_list()
  get_google_list(WHITE_LIST_URL,@white_list_emails)
end

def get_black_list()
  get_google_list(BLACK_LIST_URL,@black_list_emails)
end


@emails = Hash.new
@no_emails = Array.new
@black_list_emails = Array.new
@white_list_emails = Array.new
@s2_list_emails = Array.new
@s2_eq_list_emails = Array.new
@s2_rs_list_emails = Array.new
@lds_org_emails = Array.new
@to_be_invited_to_eq = Array.new
@to_be_invited_to_rs = Array.new

@options = parse_options()

@invite = @options[:invite]

@lds_username = ask("Enter your lds.org username:  ") { |q| q.echo = true }#@options[:lds_username] || ask("Enter your lds.org username:  ") { |q| q.echo = true }
@lds_password = ask("Enter your lds.org password:  ") { |q| q.echo = "*" }#@options[:lds_password] || ask("Enter your lds.org password:  ") { |q| q.echo = "*" }
@google_username = ask("Enter your google username:  ") { |q| q.echo = true }#@options[:google_username] || ask("Enter your google username:  ") { |q| q.echo = true }
@google_password = ask("Enter your google password:  ") { |q| q.echo = "*" }#@options[:google_password] || ask("Enter your google password:  ") { |q| q.echo = "*" }

@agent = Mechanize.new do |agent|
  #agent.log = Logger.new(STDOUT)
  #agent.follow_meta_refresh = true
  agent.user_agent_alias = 'Mac Safari'
end

puts "Getting blacklist"
get_black_list()
# get white list members
puts "Getting whitelist"

get_white_list()

# get the membership list from lds.org
puts "Getting membership list"
get_lds_members()

# get the groups lists
puts "getting s2 list"
get_s2_list(@s2_list_emails)

puts "getting eq list"
get_s2_eq_list(@s2_eq_list_emails)

puts "getting rs list"
get_s2_rs_list(@s2_rs_list_emails)

@should_be_on_lds_list = @white_list_emails + @lds_org_emails - @black_list_emails
@to_be_invited_to_lds = @should_be_on_lds_list - @s2_list_emails
@to_be_invited_to_eq_or_rs = @should_be_on_lds_list - (@s2_eq_list_emails + @s2_rs_list_emails + @white_list_emails)

# # Ask m/f/x
@to_be_invited_to_eq_or_rs.each do |email|
  member = @emails[email]
  response = ""
  until response =~ /[m|f|x]/
    print "Is #{member.lastname}, #{member.firstname} Male/Female/Skip (m/f/x): "
    # system("stty raw -echo")

    response = $stdin.gets.chomp #gets.chomp # STDIN.getc
  end

  if response == "m"
    member.sex = :male
    @to_be_invited_to_eq << member.email
  elsif response == "f"
    member.sex = :female
    @to_be_invited_to_rs << member.email
  end
end

p @to_be_invited_to_lds
p @to_be_invited_to_eq
p @to_be_invited_to_rs

invited = []
invited << invite(STANFORD_2ND_WARD_LIST,@to_be_invited_to_lds)
invited << invite(STANFORD_2ND_WARD_EQ_LIST,@to_be_invited_to_eq)
invited << invite(STANFORD_2ND_WARD_RS_LIST,@to_be_invited_to_rs)

p invited
